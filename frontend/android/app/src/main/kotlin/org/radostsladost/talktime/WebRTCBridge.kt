package org.radostsldost.talktime

import android.content.Context
import android.media.AudioManager
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
    private val methodChannel = MethodChannel(messenger, CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)

    private var peerConnectionFactory: PeerConnectionFactory? = null
    private val peerConnections = ConcurrentHashMap<String, PeerConnection>()
    private val localStreams = ConcurrentHashMap<String, MediaStream>()
    private val remoteStreams = ConcurrentHashMap<String, MediaStream>()
    private val videoRenderers = ConcurrentHashMap<Long, TextureRegistry.SurfaceTextureEntry>()
    private var eventSink: EventChannel.EventSink? = null

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
        val map = mutableMapOf<String, Any?>(
            "pcId" to pcId,
            "event" to event
        )
        map.putAll(data)
        Handler(Looper.getMainLooper()).post {
            eventSink?.success(map)
        }
    }

    private fun handleInitialize(result: MethodChannel.Result) {
        if (peerConnectionFactory != null) {
            result.success(null)
            return
        }
        PeerConnectionFactory.initialize(
            PeerConnectionFactory.InitializationOptions.builder(context).setEnableInternalTracer(true).createInitializationOptions()
        )
        val options = PeerConnectionFactory.Options().apply {
            // Use default; AEC/NS are enabled in the default audio device module
        }
        peerConnectionFactory = PeerConnectionFactory.builder()
            .setOptions(options)
            .createPeerConnectionFactory()
        result.success(null)
    }

    private fun handleCreatePeerConnection(call: MethodCall, result: MethodChannel.Result) {
        val config = call.argument<Map<String, Any>>("config") ?: emptyMap()
        val iceServers = (config["iceServers"] as? List<*>)?.mapNotNull { server ->
            val m = server as? Map<*, *> ?: return@mapNotNull null
            val urls = (m["urls"] as? List<*>)?.map { it.toString() }?.toTypedArray()
                ?: return@mapNotNull null
            PeerConnection.IceServer.builder(urls.joinToString(","))
                .setUsername((m["username"] as? String).orEmpty())
                .setPassword((m["credential"] as? String).orEmpty())
                .createIceServer()
        } ?: emptyList()

        val rtcConfig = PeerConnection.RTCConfiguration(iceServers).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
        }

        val pcId = UUID.randomUUID().toString()
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
                    val data = mutableMapOf<String, Any?>(
                        "candidate" to candidate.sdp,
                        "sdpMid" to candidate.sdpMid,
                        "sdpMLineIndex" to candidate.sdpMLineIndex
                    )
                    sendEvent(pcId, "onIceCandidate", data)
                }
            }
            override fun onIceCandidatesRemoved(candidates: Array<out IceCandidate>?) {}
            override fun onAddStream(stream: MediaStream?) {}
            override fun onRemoveStream(stream: MediaStream?) {}
            override fun onDataChannel(channel: DataChannel?) {}
            override fun onRenegotiationNeeded() {}
            override fun onAddTrack(receiver: RtpReceiver?, streams: Array<MediaStream>?) {
                if (receiver?.track() != null && streams != null && streams.isNotEmpty()) {
                    val stream: org.webrtc.MediaStream = streams.first()
                    val tr: MediaStreamTrack = receiver.track()!!
                    val streamIdStr: String = stream.getId()
                    val trackIdStr: String = tr.id()
                    val kindStr: String = tr.kind()
                    val data: HashMap<String, Any?> = hashMapOf()
                    data.put("streamId", streamIdStr)
                    data.put("trackId", trackIdStr)
                    data.put("kind", kindStr)
                    sendEvent(pcId, "onTrack", data)
                }
            }
            override fun onTrack(transceiver: RtpTransceiver?) {
                val receiver: RtpReceiver? = transceiver?.receiver
                val track: MediaStreamTrack? = receiver?.track()
                val streamId: String = track?.id()?.let { "remote-$it" } ?: ""
                if (track != null && streamId.isNotEmpty()) {
                    val trackIdStr: String = track.id()
                    val kindStr: String = track.kind()
                    val data: HashMap<String, Any?> = hashMapOf()
                    data.put("streamId", streamId)
                    data.put("trackId", trackIdStr)
                    data.put("kind", kindStr)
                    sendEvent(pcId, "onTrack", data)
                }
            }
        }) ?: run {
            result.error("CREATE_FAILED", "createPeerConnection returned null", null)
            return
        }
        peerConnections[pcId] = pc
        result.success(pcId)
    }

    private fun handleGetUserMedia(call: MethodCall, result: MethodChannel.Result) {
        val constraints = call.argument<Map<String, Any>>("constraints") ?: emptyMap()
        val streamId = "local-${UUID.randomUUID()}"
        val stream = peerConnectionFactory!!.createLocalMediaStream(streamId)

        val audioConstraints = constraints["audio"]
        val wantAudio = (audioConstraints as? Boolean) != false && audioConstraints != null
        if (wantAudio) {
            val audioSource = peerConnectionFactory!!.createAudioSource(MediaConstraints().apply {
                mandatory.add(MediaConstraints.KeyValuePair("googEchoCancellation", "true"))
                mandatory.add(MediaConstraints.KeyValuePair("googNoiseSuppression", "true"))
                mandatory.add(MediaConstraints.KeyValuePair("googAutoGainControl", "true"))
            })
            val audioTrack = peerConnectionFactory!!.createAudioTrack("audio-$streamId", audioSource)
            stream.addTrack(audioTrack)
        }

        localStreams[streamId] = stream
        val tracks = stream.audioTracks.map { mapOf("trackId" to it.id(), "kind" to "audio") } +
                stream.videoTracks.map { mapOf("trackId" to it.id(), "kind" to "video") }
        result.success(mapOf("streamId" to streamId, "tracks" to tracks))
    }

    private fun handleGetDisplayMedia(call: MethodCall, result: MethodChannel.Result) {
        result.success(null)
    }

    private fun handleCreateVideoRenderer(result: MethodChannel.Result) {
        val entry = textureRegistry.createSurfaceTexture()
        val id = entry.id()
        videoRenderers[id] = entry
        result.success(id.toLong())
    }

    private fun handleDisposeVideoRenderer(call: MethodCall, result: MethodChannel.Result) {
        val textureId = (call.argument<Number>("textureId")?.toLong()) ?: -1L
        videoRenderers.remove(textureId)?.release()
        result.success(null)
    }

    private fun handleVideoRendererSetStream(call: MethodCall, result: MethodChannel.Result) {
        result.success(null)
    }

    private fun handleEnumerateDevices(call: MethodCall, result: MethodChannel.Result) {
        val kind = call.argument<String>("kind") ?: "audioinput"
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
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

    private fun handlePcAddTrack(call: MethodCall, result: MethodChannel.Result) {
        val pcId = call.argument<String>("pcId") ?: ""
        val trackId = call.argument<String>("trackId") ?: ""
        val streamId = call.argument<String>("streamId") ?: ""
        val pc = peerConnections[pcId] ?: run { result.error("NO_PC", "PeerConnection not found", null); return }
        val stream = localStreams[streamId] ?: run { result.error("NO_STREAM", "Stream not found", null); return }
        val track = stream.audioTracks.find { it.id() == trackId } ?: stream.videoTracks.find { it.id() == trackId }
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
                val typeStr = sdp?.type?.canonicalForm()
                result.success(mapOf("sdp" to sdp?.description, "type" to typeStr))
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
                val typeStr = sdp?.type?.canonicalForm()
                result.success(mapOf("sdp" to sdp?.description, "type" to typeStr))
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
            }, SessionDescription(SessionDescription.Type.fromCanonicalForm(type), sdp!!))
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
        result.success(if (desc != null) mapOf("sdp" to desc.description, "type" to desc.type.canonicalForm()) else null)
    }

    private fun handlePcGetTransceivers(call: MethodCall, result: MethodChannel.Result) {
        val pcId = call.argument<String>("pcId") ?: ""
        val pc = peerConnections[pcId] ?: run { result.success(emptyList<Map<String, Any>>()); return }
        val list = pc.transceivers.map { t ->
            mapOf(
                "senderId" to t.sender.id(),
                "trackId" to (t.receiver.track()?.id()),
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

    private fun handleTrackSetEnabled(call: MethodCall, result: MethodChannel.Result) {
        val trackId = call.argument<String>("trackId") ?: ""
        val enabled = call.argument<Boolean>("enabled") ?: true
        for (stream in localStreams.values) {
            val audio = stream.audioTracks.find { it.id() == trackId }
            val video = stream.videoTracks.find { it.id() == trackId }
            val track = audio ?: video
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
        result.success(null)
    }

    private fun handleStreamGetAudioTracks(call: MethodCall, result: MethodChannel.Result) {
        val streamId = call.argument<String>("streamId") ?: ""
        val stream = localStreams[streamId] ?: remoteStreams[streamId]
        result.success(stream?.audioTracks?.map { mapOf("trackId" to it.id()) } ?: emptyList<Map<String, String>>())
    }

    private fun handleStreamGetVideoTracks(call: MethodCall, result: MethodChannel.Result) {
        val streamId = call.argument<String>("streamId") ?: ""
        val stream = localStreams[streamId] ?: remoteStreams[streamId]
        result.success(stream?.videoTracks?.map { mapOf("trackId" to it.id()) } ?: emptyList<Map<String, String>>())
    }

    private fun handleStreamAddTrack(call: MethodCall, result: MethodChannel.Result) {
        result.success(null)
    }

    private fun handleStreamRemoveTrack(call: MethodCall, result: MethodChannel.Result) {
        result.success(null)
    }

    private fun handleStreamDispose(call: MethodCall, result: MethodChannel.Result) {
        val streamId = call.argument<String>("streamId") ?: ""
        localStreams.remove(streamId)?.dispose()
        remoteStreams.remove(streamId)?.dispose()
        result.success(null)
    }
}
