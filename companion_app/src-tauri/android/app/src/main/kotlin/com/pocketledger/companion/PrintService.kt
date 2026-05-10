package com.pocketledger.companion

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.IBinder

class PrintService : Service() {

    companion object {
        const val CHANNEL_ID = "pocketledger_print"
        const val NOTIFICATION_ID = 888
    }

    override fun onCreate() {
        super.onCreate()
        createChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // The Rust HTTP server runs in the main process.
        // This service just keeps Android from killing the process when
        // the user switches to Chrome or another app.
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "PocketLedger Print Service",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Keeps the local print server running"
            setShowBadge(false)
        }
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification =
        Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("PocketLedger")
            .setContentText("Print server active on localhost:8765")
            .setSmallIcon(android.R.drawable.ic_print)
            .setOngoing(true)
            .build()
}
