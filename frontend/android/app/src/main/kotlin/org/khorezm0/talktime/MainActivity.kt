package org.radostsldost.talktime

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
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
