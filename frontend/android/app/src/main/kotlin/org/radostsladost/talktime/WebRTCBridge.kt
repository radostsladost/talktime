package org.radostsldost.talktime

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import org.webrtc.*
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

private const val CHANNEL = "talktime_webrtc"
private const val EVENT_CHANNEL = "talktime_webrtc_events"
private const val TAG = "WebRTCBridge"

class WebRTCBridge(
    private val context: Context,
    messenger: BinaryMessenger,
    private val textureRegistry: TextureRegistry
) {
    companion object {
        const val SCREEN_CAPTURE_REQUEST = 1001
    }

    private val methodChannel = MethodChannel(messenger, CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)

    private var eglBase: EglBase? = null
    private var peerConnectionFactory: PeerConnectionFactory? = null
    private val peerConnections = ConcurrentHashMap<String, PeerConnection>()
    private val localStreams = ConcurrentHashMap<String, MediaStream>()
    private val remoteStreams = ConcurrentHashMap<String, MediaStream>()
    private var eventSink: EventChannel.EventSink? = null

    private var cameraCapturer: CameraVideoCapturer? = null
    private var cameraSurfaceHelper: SurfaceTextureHelper? = null

    private var screenCapturer: VideoCapturer? = null
    private var screenSurfaceHelper: SurfaceTextureHelper? = null
    private var pendingDisplayMediaResult: MethodChannel.Result? = null
    private var pendingDisplayMediaStreamId: String? = null

    private val allVideoTracks = ConcurrentHashMap<String, VideoTrack>()

    // FlutterVideoSink: extends WebRTC's EglRenderer to draw frames
    // onto a Flutter SurfaceTexture. EGL surface is created lazily on
    // the first frame, matching the flutter-webrtc reference implementation.
    private inner class FlutterVideoSink(
        val textureEntry: TextureRegistry.SurfaceTextureEntry
    ) : EglRenderer("FlutterSink-${textureEntry.id()}") {
        var videoTrack: VideoTrack? = null
        @Volatile private var surfaceCreated = false
        private var rotatedWidth = 0
        private var rotatedHeight = 0

        init {
            init(eglBase?.eglBaseContext, EglBase.CONFIG_RECORDABLE, GlRectDrawer(), true)
        }

        override fun onFrame(frame: VideoFrame) {
            val w = frame.rotatedWidth
            val h = frame.rotatedHeight

            if (!surfaceCreated && w > 0 && h > 0) {
                textureEntry.surfaceTexture().setDefaultBufferSize(w, h)
                createEglSurface(textureEntry.surfaceTexture())
                surfaceCreated = true
                rotatedWidth = w
                rotatedHeight = h
                Log.i(TAG, "FlutterVideoSink: EGL surface created ${w}x${h}")
            } else if (surfaceCreated && w > 0 && h > 0 &&
                       (w != rotatedWidth || h != rotatedHeight)) {
                rotatedWidth = w
                rotatedHeight = h
                textureEntry.surfaceTexture().setDefaultBufferSize(w, h)
            }

            super.onFrame(frame)
        }
    }

    private val videoRenderers = ConcurrentHashMap<Long, FlutterVideoSink>()

    init {
        methodChannel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "initialize" -> handleInitialize(result)
                    "createPeerConnection" -> handleCreatePeerConnection(call, result)
                    "getUserMedia" -> handleGetUserMedia(call, result)
                    "getDisplayMedia" -> handleGetDisplayMedia(call, result)
                    "createVideoRenderer" -> handleCreateVideoRenderer(result)
                    "disposeVideoRenderer" -> handleDisposeVideoRenderer(call, result)
                    "videoRendererSetStream" -> handleVideoRendererSetStream(call, result)
                    "enumerateDevices" -> handleEnumerateDevices(call, result)
                    "setSpeakerphoneOn" -> handleSetSpeakerphoneOn(call, result)
                    "pcAddTrack" -> handlePcAddTrack(call, result)
                    "pcCreateOffer" -> handlePcCreateOffer(call, result)
                    "pcCreateAnswer" -> handlePcCreateAnswer(call, result)
                    "pcSetLocalDescription" -> handlePcSetLocalDescription(call, result)
                    "pcSetRemoteDescription" -> handlePcSetRemoteDescription(call, result)
                    "pcAddIceCandidate" -> handlePcAddIceCandidate(call, result)
                    "pcGetSignalingState" -> handlePcGetSignalingState(call, result)
                    "pcGetRemoteDescription" -> handlePcGetRemoteDescription(call, result)
                    "pcGetTransceivers" -> handlePcGetTransceivers(call, result)
                    "pcClose" -> handlePcClose(call, result)
                    "senderReplaceTrack" -> handleSenderReplaceTrack(call, result)
                    "trackSetEnabled" -> handleTrackSetEnabled(call, result)
                    "trackStop" -> handleTrackStop(call, result)
                    "streamGetAudioTracks" -> handleStreamGetAudioTracks(call, result)
                    "streamGetVideoTracks" -> handleStreamGetVideoTracks(call, result)
                    "streamAddTrack" -> handleStreamAddTrack(call, result)
                    "streamRemoveTrack" -> handleStreamRemoveTrack(call, result)
                    "streamDispose" -> handleStreamDispose(call, result)
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error handling ${call.method}", e)
                result.error("ERROR", e.message, null)
            }
        }
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }
            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    private fun sendEvent(pcId: String, event: String, data: Map<String, Any?>) {
        val map = mutableMapOf<String, Any?>("pcId" to pcId, "event" to event)
        map.putAll(data)
        Handler(Looper.getMainLooper()).post { eventSink?.success(map) }
    }

    // ================================================================
    // INITIALIZATION
    // ================================================================

    private fun handleInitialize(result: MethodChannel.Result) {
        if (peerConnectionFactory != null) {
            result.success(null)
            return
        }

        eglBase = EglBase.create()

        PeerConnectionFactory.initialize(
            PeerConnectionFactory.InitializationOptions.builder(context)
                .setEnableInternalTracer(true)
                .createInitializationOptions()
        )

        val encoderFactory = DefaultVideoEncoderFactory(
            eglBase!!.eglBaseContext, true, true
        )
        val decoderFactory = DefaultVideoDecoderFactory(eglBase!!.eglBaseContext)

        peerConnectionFactory = PeerConnectionFactory.builder()
            .setVideoEncoderFactory(encoderFactory)
            .setVideoDecoderFactory(decoderFactory)
            .createPeerConnectionFactory()

        result.success(null)
    }

    // ================================================================
    // PEER CONNECTION
    // ================================================================

    private fun handleCreatePeerConnection(call: MethodCall, result: MethodChannel.Result) {
        val config = call.argument<Map<String, Any>>("config") ?: emptyMap()
        val iceServers = (config["iceServers"] as? List<*>)?.mapNotNull { server ->
            val m = server as? Map<*, *> ?: return@mapNotNull null
            val urls = (m["urls"] as? List<*>)?.map { it.toString() }
                ?: return@mapNotNull null
            PeerConnection.IceServer.builder(urls)
                .setUsername((m["username"] as? String).orEmpty())
                .setPassword((m["credential"] as? String).orEmpty())
                .createIceServer()
        } ?: emptyList()

        val rtcConfig = PeerConnection.RTCConfiguration(iceServers).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
        }

        val pcId = UUID.randomUUID().toString()
        val handledTrackIds = mutableSetOf<String>()
        val pc = peerConnectionFactory!!.createPeerConnection(rtcConfig, object : PeerConnection.Observer {
            override fun onSignalingChange(state: PeerConnection.SignalingState?) {}
            override fun onIceConnectionChange(state: PeerConnection.IceConnectionState?) {
                if (state != null) {
                    sendEvent(pcId, "onIceConnectionState", mapOf("state" to state.name.lowercase()))
                }
            }
            override fun onIceConnectionReceivingChange(receiving: Boolean) {}
            override fun onIceGatheringChange(state: PeerConnection.IceGatheringState?) {}
            override fun onIceCandidate(candidate: IceCandidate?) {
                if (candidate != null) {
                    sendEvent(pcId, "onIceCandidate", mapOf(
                        "candidate" to candidate.sdp,
                        "sdpMid" to candidate.sdpMid,
                        "sdpMLineIndex" to candidate.sdpMLineIndex
                    ))
                }
            }
            override fun onIceCandidatesRemoved(candidates: Array<out IceCandidate>?) {}
            override fun onAddStream(stream: MediaStream?) {}
            override fun onRemoveStream(stream: MediaStream?) {}
            override fun onDataChannel(channel: DataChannel?) {}
            override fun onRenegotiationNeeded() {}
            override fun onAddTrack(receiver: RtpReceiver?, streams: Array<MediaStream>?) {
                if (receiver?.track() != null && streams != null && streams.isNotEmpty()) {
                    val track = receiver.track()!!
                    if (!handledTrackIds.add(track.id())) return

                    val stream = streams.first()
                    val streamId = stream.getId()

                    remoteStreams[streamId] = stream
                    if (track is VideoTrack) allVideoTracks[track.id()] = track

                    Log.i(TAG, "onAddTrack: stream=$streamId track=${track.id()} kind=${track.kind()}")
                    sendEvent(pcId, "onTrack", hashMapOf(
                        "streamId" to streamId,
                        "trackId" to track.id(),
                        "kind" to track.kind()
                    ))
                }
            }
            override fun onTrack(transceiver: RtpTransceiver?) {
                val track = transceiver?.receiver?.track() ?: return
                if (!handledTrackIds.add(track.id())) return

                Log.i(TAG, "onTrack (fallback): track=${track.id()} kind=${track.kind()}")

                if (track is VideoTrack) {
                    allVideoTracks[track.id()] = track
                    val existingStreamId = remoteStreams.entries.firstOrNull()?.key
                    if (existingStreamId != null) {
                        try {
                            remoteStreams[existingStreamId]?.addTrack(track)
                        } catch (e: Exception) {
                            Log.w(TAG, "onTrack: could not add video to existing stream: ${e.message}")
                        }
                    }
                }

                val streamId = "remote-${track.id()}"
                sendEvent(pcId, "onTrack", hashMapOf(
                    "streamId" to streamId,
                    "trackId" to track.id(),
                    "kind" to track.kind()
                ))
            }
        }) ?: run {
            result.error("CREATE_FAILED", "createPeerConnection returned null", null)
            return
        }
        peerConnections[pcId] = pc
        result.success(pcId)
    }

    // ================================================================
    // USER MEDIA (Camera + Audio)
    // ================================================================

    private fun handleGetUserMedia(call: MethodCall, result: MethodChannel.Result) {
        val constraints = call.argument<Map<String, Any>>("constraints") ?: emptyMap()
        Log.i(TAG, "getUserMedia: constraints=$constraints")
        val streamId = "local-${UUID.randomUUID()}"
        val stream = peerConnectionFactory!!.createLocalMediaStream(streamId)

        val audioConstraints = constraints["audio"]
        val wantAudio = audioConstraints != null && audioConstraints != false
        if (wantAudio) {
            val audioSource = peerConnectionFactory!!.createAudioSource(MediaConstraints().apply {
                mandatory.add(MediaConstraints.KeyValuePair("googEchoCancellation", "true"))
                mandatory.add(MediaConstraints.KeyValuePair("googNoiseSuppression", "true"))
                mandatory.add(MediaConstraints.KeyValuePair("googAutoGainControl", "true"))
            })
            val audioTrack = peerConnectionFactory!!.createAudioTrack("audio-$streamId", audioSource)
            stream.addTrack(audioTrack)
        }

        val videoConstraints = constraints["video"]
        if (videoConstraints != null && videoConstraints != false) {
            try {
                val enumerator: CameraEnumerator = if (Camera2Enumerator.isSupported(context)) {
                    Camera2Enumerator(context)
                } else {
                    @Suppress("DEPRECATION")
                    Camera1Enumerator(true)
                }
                val deviceNames = enumerator.deviceNames

                val facingMode = if (videoConstraints is Map<*, *>) {
                    videoConstraints["facingMode"] as? String ?: "user"
                } else "user"
                val isFront = facingMode == "user"

                val deviceName = deviceNames.firstOrNull {
                    if (isFront) enumerator.isFrontFacing(it) else enumerator.isBackFacing(it)
                } ?: deviceNames.firstOrNull()

                if (deviceName != null) {
                    releaseCamera()

                    val helper = SurfaceTextureHelper.create("CamCapture", eglBase!!.eglBaseContext)
                    cameraSurfaceHelper = helper

                    val capturer = enumerator.createCapturer(deviceName, null)
                    val source = peerConnectionFactory!!.createVideoSource(capturer.isScreencast)
                    capturer.initialize(helper, context, source.capturerObserver)

                    var width = 640; var height = 480; var fps = 30
                    if (videoConstraints is Map<*, *>) {
                        (videoConstraints["width"] as? Map<*, *>)?.get("ideal")
                            ?.let { width = (it as Number).toInt() }
                        (videoConstraints["height"] as? Map<*, *>)?.get("ideal")
                            ?.let { height = (it as Number).toInt() }
                        (videoConstraints["frameRate"] as? Map<*, *>)?.get("ideal")
                            ?.let { fps = (it as Number).toInt() }
                    }

                    capturer.startCapture(width, height, fps)
                    cameraCapturer = capturer

                    val videoTrack = peerConnectionFactory!!.createVideoTrack("video-$streamId", source)
                    videoTrack.setEnabled(true)
                    stream.addTrack(videoTrack)
                    allVideoTracks[videoTrack.id()] = videoTrack
                    Log.i(TAG, "Camera video track created: ${videoTrack.id()}, device=$deviceName, ${width}x${height}@${fps}")
                } else {
                    Log.w(TAG, "No camera device found")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to create video track", e)
            }
        }

        localStreams[streamId] = stream
        val tracks = stream.audioTracks.map { mapOf("trackId" to it.id(), "kind" to "audio") } +
                stream.videoTracks.map { mapOf("trackId" to it.id(), "kind" to "video") }
        Log.i(TAG, "getUserMedia result: streamId=$streamId, tracks=${tracks.size} (audio=${stream.audioTracks.size}, video=${stream.videoTracks.size})")
        result.success(mapOf("streamId" to streamId, "tracks" to tracks))
    }

    // ================================================================
    // DISPLAY MEDIA (Screen Share via MediaProjection)
    // ================================================================

    private fun handleGetDisplayMedia(call: MethodCall, result: MethodChannel.Result) {
        val activity = context as? Activity
        if (activity == null) {
            Log.e(TAG, "getDisplayMedia requires Activity context")
            result.success(null)
            return
        }

        pendingDisplayMediaResult = result
        pendingDisplayMediaStreamId = "screen-${UUID.randomUUID()}"

        val mgr = context.getSystemService(Context.MEDIA_PROJECTION_SERVICE)
                as MediaProjectionManager
        activity.startActivityForResult(mgr.createScreenCaptureIntent(), SCREEN_CAPTURE_REQUEST)
    }

    fun onScreenCaptureResult(resultCode: Int, data: Intent?): Boolean {
        val result = pendingDisplayMediaResult ?: return false
        pendingDisplayMediaResult = null

        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(null)
            return true
        }

        try {
            val streamId = pendingDisplayMediaStreamId ?: "screen-${UUID.randomUUID()}"
            val stream = peerConnectionFactory!!.createLocalMediaStream(streamId)

            releaseScreenCapturer()

            val capturer = ScreenCapturerAndroid(data, object : MediaProjection.Callback() {
                override fun onStop() { Log.i(TAG, "Screen capture stopped") }
            })

            val helper = SurfaceTextureHelper.create("ScreenCapture", eglBase!!.eglBaseContext)
            screenSurfaceHelper = helper

            val source = peerConnectionFactory!!.createVideoSource(capturer.isScreencast)
            capturer.initialize(helper, context, source.capturerObserver)
            capturer.startCapture(1280, 720, 30)
            screenCapturer = capturer

            val videoTrack = peerConnectionFactory!!.createVideoTrack("video-$streamId", source)
            videoTrack.setEnabled(true)
            stream.addTrack(videoTrack)
            allVideoTracks[videoTrack.id()] = videoTrack

            localStreams[streamId] = stream
            Log.i(TAG, "Screen capture track created: ${videoTrack.id()}")

            val tracks = stream.videoTracks.map { mapOf("trackId" to it.id(), "kind" to "video") }
            result.success(mapOf("streamId" to streamId, "tracks" to tracks))
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start screen capture", e)
            result.success(null)
        }
        return true
    }

    // ================================================================
    // VIDEO RENDERER
    // ================================================================

    private fun handleCreateVideoRenderer(result: MethodChannel.Result) {
        val entry = textureRegistry.createSurfaceTexture()
        val id = entry.id()
        val sink = FlutterVideoSink(entry)
        videoRenderers[id] = sink
        Log.i(TAG, "Video renderer created: textureId=$id")
        result.success(id.toLong())
    }

    private fun handleDisposeVideoRenderer(call: MethodCall, result: MethodChannel.Result) {
        val textureId = call.argument<Number>("textureId")?.toLong() ?: -1L
        val sink = videoRenderers.remove(textureId)
        if (sink != null) {
            sink.videoTrack?.removeSink(sink)
            sink.release()
            sink.textureEntry.release()
        }
        result.success(null)
    }

    private fun handleVideoRendererSetStream(call: MethodCall, result: MethodChannel.Result) {
        val textureId = call.argument<Number>("textureId")?.toLong() ?: -1L
        val streamId = call.argument<String>("streamId") ?: ""

        Log.i(TAG, "videoRendererSetStream: textureId=$textureId streamId=$streamId")

        val sink = videoRenderers[textureId]
        if (sink == null) {
            Log.w(TAG, "videoRendererSetStream: renderer $textureId not found")
            result.success(null)
            return
        }

        sink.videoTrack?.removeSink(sink)
        sink.videoTrack = null

        val stream = localStreams[streamId] ?: remoteStreams[streamId]
        var videoTrack = stream?.videoTracks?.firstOrNull() as? VideoTrack

        if (videoTrack == null && stream != null) {
            Log.w(TAG, "videoRendererSetStream: stream found but no video tracks (audio=${stream.audioTracks.size})")
        }

        // Fallback: search allVideoTracks by matching IDs (guard against disposed tracks)
        if (videoTrack == null) {
            val deadKeys = mutableListOf<String>()
            for ((key, t) in allVideoTracks) {
                try {
                    val tid = t.id()
                    if (tid.contains(streamId) || streamId.contains(tid)) {
                        videoTrack = t
                        break
                    }
                } catch (_: IllegalStateException) {
                    deadKeys.add(key)
                }
            }
            deadKeys.forEach { allVideoTracks.remove(it) }
        }

        if (videoTrack != null) {
            videoTrack.addSink(sink)
            sink.videoTrack = videoTrack
            Log.i(TAG, "videoRendererSetStream: connected track ${videoTrack.id()} to renderer $textureId")
        } else {
            Log.w(TAG, "videoRendererSetStream: no video track found for stream $streamId " +
                    "(localStreams=${localStreams.keys}, remoteStreams=${remoteStreams.keys}, allTracks=${allVideoTracks.keys})")
        }

        result.success(null)
    }

    // ================================================================
    // DEVICE ENUMERATION & SPEAKER
    // ================================================================

    private fun handleEnumerateDevices(call: MethodCall, result: MethodChannel.Result) {
        val kind = call.argument<String>("kind") ?: "audioinput"
        val devices = when (kind) {
            "audioinput" -> listOf(
                mapOf("deviceId" to "default", "label" to "Default microphone", "kind" to kind),
                mapOf("deviceId" to "speaker", "label" to "Speaker", "kind" to kind)
            )
            "audiooutput" -> listOf(
                mapOf("deviceId" to "default", "label" to "Default", "kind" to kind),
                mapOf("deviceId" to "speaker", "label" to "Speaker", "kind" to kind),
                mapOf("deviceId" to "earpiece", "label" to "Earpiece", "kind" to kind)
            )
            else -> emptyList()
        }
        result.success(devices)
    }

    private fun handleSetSpeakerphoneOn(call: MethodCall, result: MethodChannel.Result) {
        val on = call.argument<Boolean>("on") ?: false
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        @Suppress("DEPRECATION")
        am.isSpeakerphoneOn = on
        result.success(null)
    }

    // ================================================================
    // PEER CONNECTION OPERATIONS
    // ================================================================

    private fun handlePcAddTrack(call: MethodCall, result: MethodChannel.Result) {
        val pcId = call.argument<String>("pcId") ?: ""
        val trackId = call.argument<String>("trackId") ?: ""
        val streamId = call.argument<String>("streamId") ?: ""
        val pc = peerConnections[pcId]
            ?: run { result.error("NO_PC", "PeerConnection not found", null); return }
        val stream = localStreams[streamId]
            ?: run { result.error("NO_STREAM", "Stream not found", null); return }
        val track = stream.audioTracks.find { it.id() == trackId }
            ?: stream.videoTracks.find { it.id() == trackId }
        if (track != null) {
            pc.addTrack(track, listOf(streamId))
            result.success(null)
        } else {
            result.error("NO_TRACK", "Track not found", null)
        }
    }

    private fun handlePcCreateOffer(call: MethodCall, result: MethodChannel.Result) {
        val pcId = call.argument<String>("pcId") ?: ""
        val pc = peerConnections[pcId] ?: run { result.error("NO_PC", null, null); return }
        pc.createOffer(object : SdpObserver {
            override fun onCreateSuccess(sdp: SessionDescription?) {
                result.success(mapOf("sdp" to sdp?.description, "type" to sdp?.type?.canonicalForm()))
            }
            override fun onCreateFailure(error: String?) { result.error("CREATE_OFFER", error, null) }
            override fun onSetSuccess() {}
            override fun onSetFailure(error: String?) {}
        }, MediaConstraints())
    }

    private fun handlePcCreateAnswer(call: MethodCall, result: MethodChannel.Result) {
        val pcId = call.argument<String>("pcId") ?: ""
        val pc = peerConnections[pcId] ?: run { result.error("NO_PC", null, null); return }
        pc.createAnswer(object : SdpObserver {
            override fun onCreateSuccess(sdp: SessionDescription?) {
                result.success(mapOf("sdp" to sdp?.description, "type" to sdp?.type?.canonicalForm()))
            }
            override fun onCreateFailure(error: String?) { result.error("CREATE_ANSWER", error, null) }
            override fun onSetSuccess() {}
            override fun onSetFailure(error: String?) {}
        }, MediaConstraints())
    }

    private fun handlePcSetLocalDescription(call: MethodCall, result: MethodChannel.Result) {
        val pcId = call.argument<String>("pcId") ?: ""
        val sdp = call.argument<String>("sdp")
        val type = call.argument<String>("type") ?: "offer"
        val pc = peerConnections[pcId] ?: run { result.error("NO_PC", null, null); return }
        if (type == "rollback") {
            result.success(null)
        } else if (sdp != null) {
            pc.setLocalDescription(object : SdpObserver {
                override fun onCreateSuccess(p0: SessionDescription?) {}
                override fun onCreateFailure(p0: String?) {}
                override fun onSetSuccess() { result.success(null) }
                override fun onSetFailure(p0: String?) { result.error("SET_LOCAL", p0, null) }
            }, SessionDescription(SessionDescription.Type.fromCanonicalForm(type), sdp))
        } else {
            result.success(null)
        }
    }

    private fun handlePcSetRemoteDescription(call: MethodCall, result: MethodChannel.Result) {
        val pcId = call.argument<String>("pcId") ?: ""
        val sdp = call.argument<String>("sdp") ?: ""
        val type = call.argument<String>("type") ?: "offer"
        val pc = peerConnections[pcId] ?: run { result.error("NO_PC", null, null); return }
        pc.setRemoteDescription(object : SdpObserver {
            override fun onCreateSuccess(p0: SessionDescription?) {}
            override fun onCreateFailure(p0: String?) {}
            override fun onSetSuccess() { result.success(null) }
            override fun onSetFailure(p0: String?) { result.error("SET_REMOTE", p0, null) }
        }, SessionDescription(SessionDescription.Type.fromCanonicalForm(type), sdp))
    }

    private fun handlePcAddIceCandidate(call: MethodCall, result: MethodChannel.Result) {
        val pcId = call.argument<String>("pcId") ?: ""
        val candidate = call.argument<String>("candidate") ?: ""
        val sdpMid = call.argument<String>("sdpMid") ?: ""
        val sdpMLineIndex = call.argument<Int>("sdpMLineIndex") ?: 0
        val pc = peerConnections[pcId] ?: run { result.error("NO_PC", null, null); return }
        val ice = IceCandidate(sdpMid, sdpMLineIndex, candidate)
        pc.addIceCandidate(ice, object : org.webrtc.AddIceObserver {
            override fun onAddSuccess() { result.success(null) }
            override fun onAddFailure(error: String?) { result.error("ADD_ICE", error, null) }
        })
    }

    private fun handlePcGetSignalingState(call: MethodCall, result: MethodChannel.Result) {
        val pcId = call.argument<String>("pcId") ?: ""
        val pc = peerConnections[pcId] ?: run { result.success("stable"); return }
        result.success(pc.signalingState().name.lowercase().replace('_', '-'))
    }

    private fun handlePcGetRemoteDescription(call: MethodCall, result: MethodChannel.Result) {
        val pcId = call.argument<String>("pcId") ?: ""
        val pc = peerConnections[pcId] ?: run { result.success(null); return }
        val desc = pc.remoteDescription
        result.success(
            if (desc != null) mapOf("sdp" to desc.description, "type" to desc.type.canonicalForm())
            else null
        )
    }

    private fun handlePcGetTransceivers(call: MethodCall, result: MethodChannel.Result) {
        val pcId = call.argument<String>("pcId") ?: ""
        val pc = peerConnections[pcId]
            ?: run { result.success(emptyList<Map<String, Any>>()); return }
        val list = pc.transceivers.map { t ->
            mapOf(
                "senderId" to t.sender.id(),
                "senderTrackId" to (t.sender.track()?.id()),
                "senderTrackKind" to (t.sender.track()?.kind()),
                "receiverTrackId" to (t.receiver.track()?.id()),
                "receiverTrackKind" to (t.receiver.track()?.kind()),
                "kind" to (t.mediaType?.toString()?.lowercase() ?: "video")
            )
        }
        result.success(list)
    }

    private fun handlePcClose(call: MethodCall, result: MethodChannel.Result) {
        val pcId = call.argument<String>("pcId") ?: ""
        peerConnections.remove(pcId)?.dispose()
        result.success(null)
    }

    // ================================================================
    // SENDER REPLACE TRACK
    // ================================================================

    private fun handleSenderReplaceTrack(call: MethodCall, result: MethodChannel.Result) {
        val pcId = call.argument<String>("pcId") ?: ""
        val senderId = call.argument<String>("senderId") ?: ""
        val trackId = call.argument<String>("trackId")

        val pc = peerConnections[pcId]
            ?: run { result.error("NO_PC", null, null); return }

        val sender = pc.senders.find { it.id() == senderId }
        if (sender == null) {
            Log.w(TAG, "senderReplaceTrack: sender $senderId not found, trying by track kind")
            val track: MediaStreamTrack? = if (trackId != null) {
                localStreams.values.asSequence().flatMap { s ->
                    (s.audioTracks.asSequence() + s.videoTracks.asSequence())
                }.find { it.id() == trackId }
            } else null

            val targetKind = track?.kind() ?: "video"
            val fallbackSender = pc.senders.find { s ->
                s.track()?.kind() == targetKind || (s.track() == null && targetKind == "video")
            }
            if (fallbackSender != null) {
                fallbackSender.setTrack(track, false)
                result.success(null)
            } else {
                result.error("NO_SENDER", "Sender not found: $senderId", null)
            }
            return
        }

        val track: MediaStreamTrack? = if (trackId != null) {
            localStreams.values.asSequence().flatMap { s ->
                (s.audioTracks.asSequence() + s.videoTracks.asSequence())
            }.find { it.id() == trackId }
        } else null

        sender.setTrack(track, false)
        result.success(null)
    }

    // ================================================================
    // TRACK OPERATIONS
    // ================================================================

    private fun handleTrackSetEnabled(call: MethodCall, result: MethodChannel.Result) {
        val trackId = call.argument<String>("trackId") ?: ""
        val enabled = call.argument<Boolean>("enabled") ?: true

        val allStreams = localStreams.values + remoteStreams.values
        for (stream in allStreams) {
            val track = stream.audioTracks.find { it.id() == trackId }
                ?: stream.videoTracks.find { it.id() == trackId }
            if (track != null) {
                track.setEnabled(enabled)
                result.success(null)
                return
            }
        }

        Log.w(TAG, "trackSetEnabled: track not found id=$trackId")
        result.success(null)
    }

    private fun handleTrackStop(call: MethodCall, result: MethodChannel.Result) {
        val trackId = call.argument<String>("trackId") ?: ""
        for (stream in localStreams.values) {
            if (stream.videoTracks.any { it.id() == trackId }) {
                releaseCamera()
                releaseScreenCapturer()
                break
            }
        }
        result.success(null)
    }

    private fun releaseCamera() {
        try { cameraCapturer?.stopCapture() } catch (_: Exception) {}
        try { cameraCapturer?.dispose() } catch (_: Exception) {}
        cameraCapturer = null
        try { cameraSurfaceHelper?.dispose() } catch (_: Exception) {}
        cameraSurfaceHelper = null
        Log.i(TAG, "Camera released")
    }

    private fun releaseScreenCapturer() {
        try { screenCapturer?.stopCapture() } catch (_: Exception) {}
        try { screenCapturer?.dispose() } catch (_: Exception) {}
        screenCapturer = null
        try { screenSurfaceHelper?.dispose() } catch (_: Exception) {}
        screenSurfaceHelper = null
        Log.i(TAG, "Screen capturer released")
    }

    // ================================================================
    // STREAM OPERATIONS
    // ================================================================

    private fun handleStreamGetAudioTracks(call: MethodCall, result: MethodChannel.Result) {
        val streamId = call.argument<String>("streamId") ?: ""
        val stream = localStreams[streamId] ?: remoteStreams[streamId]
        result.success(
            stream?.audioTracks?.map { mapOf("trackId" to it.id()) }
                ?: emptyList<Map<String, String>>()
        )
    }

    private fun handleStreamGetVideoTracks(call: MethodCall, result: MethodChannel.Result) {
        val streamId = call.argument<String>("streamId") ?: ""
        val stream = localStreams[streamId] ?: remoteStreams[streamId]
        result.success(
            stream?.videoTracks?.map { mapOf("trackId" to it.id()) }
                ?: emptyList<Map<String, String>>()
        )
    }

    private fun handleStreamAddTrack(call: MethodCall, result: MethodChannel.Result) {
        val streamId = call.argument<String>("streamId") ?: ""
        val trackId = call.argument<String>("trackId") ?: ""
        val stream = localStreams[streamId] ?: run { result.success(null); return }

        for (s in localStreams.values) {
            val audioTrack = s.audioTracks.find { it.id() == trackId }
            if (audioTrack != null) {
                stream.addTrack(audioTrack)
                result.success(null)
                return
            }
            val videoTrack = s.videoTracks.find { it.id() == trackId }
            if (videoTrack != null) {
                stream.addTrack(videoTrack)
                result.success(null)
                return
            }
        }

        Log.w(TAG, "streamAddTrack: track $trackId not found")
        result.success(null)
    }

    private fun handleStreamRemoveTrack(call: MethodCall, result: MethodChannel.Result) {
        val streamId = call.argument<String>("streamId") ?: ""
        val trackId = call.argument<String>("trackId") ?: ""
        val stream = localStreams[streamId] ?: run { result.success(null); return }

        val audioTrack = stream.audioTracks.find { it.id() == trackId }
        if (audioTrack != null) {
            stream.removeTrack(audioTrack)
            result.success(null)
            return
        }
        val videoTrack = stream.videoTracks.find { it.id() == trackId }
        if (videoTrack != null) {
            stream.removeTrack(videoTrack)
            result.success(null)
            return
        }

        result.success(null)
    }

    private fun handleStreamDispose(call: MethodCall, result: MethodChannel.Result) {
        val streamId = call.argument<String>("streamId") ?: ""
        val wasLocal = localStreams.remove(streamId)
        if (wasLocal != null) {
            releaseCamera()
            releaseScreenCapturer()
            wasLocal.dispose()
        }
        remoteStreams.remove(streamId)?.dispose()
        result.success(null)
    }
}
