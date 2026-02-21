package org.radostsldost.talktime

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.os.Build
import android.media.AudioManager
import android.media.AudioDeviceInfo
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "TalkTimeAudio"
    }

    private var webrtcBridge: WebRTCBridge? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == WebRTCBridge.SCREEN_CAPTURE_REQUEST) {
            webrtcBridge?.onScreenCaptureResult(resultCode, data)
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        webrtcBridge = WebRTCBridge(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
            flutterEngine.renderer
        )
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "audio_manager"
        )
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setAudioMode" -> {
                    val mode = call.argument<Int>("mode") ?: 0
                    val am = getSystemService(AudioManager::class.java)
                    am.mode = mode  // 0 = NORMAL, 3 = MODE_IN_COMMUNICATION (enables system AEC)
                    result.success(null)
                }

                "setCommunicationDevice" -> {
                    val useSpeaker = call.argument<Boolean>("speaker") ?: false
                    val am = getSystemService(AudioManager::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        am.mode = AudioManager.MODE_IN_COMMUNICATION
                        val devices = am.getAvailableCommunicationDevices()
                        val target = if (useSpeaker) {
                            devices.find { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                        } else {
                            devices.find { it.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE }
                        }
                        if (target != null) {
                            val ok = am.setCommunicationDevice(target)
                            result.success(ok)
                        } else {
                            @Suppress("DEPRECATION")
                            am.isSpeakerphoneOn = useSpeaker
                            result.success(true)
                        }
                    } else {
                        @Suppress("DEPRECATION")
                        am.isSpeakerphoneOn = useSpeaker
                        am.mode = AudioManager.MODE_IN_COMMUNICATION
                        result.success(true)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(NotificationManager::class.java)

            // Create "calls" channel - used by the plugin for foreground service
            val callsChannel = NotificationChannel(
                "calls",
                "Incoming Call",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Channel for incoming calls"
                enableVibration(true)
                enableLights(true)
            }
            notificationManager.createNotificationChannel(callsChannel)

            // Create "Incoming Call" channel - as specified in CallKitParams
            val incomingCallChannel = NotificationChannel(
                "Incoming Call",
                "Incoming Call",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications for incoming calls"
                enableVibration(true)
                enableLights(true)
            }
            notificationManager.createNotificationChannel(incomingCallChannel)

            // Create "Missed Call" channel
            val missedCallChannel = NotificationChannel(
                "Missed Call",
                "Missed Call",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Notifications for missed calls"
            }
            notificationManager.createNotificationChannel(missedCallChannel)
        }
    }
}
