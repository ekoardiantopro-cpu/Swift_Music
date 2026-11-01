package com.swiftmusic.swift_music

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder

class SpotifyConnectService : Service() {
    private var multicastLock: WifiManager.MulticastLock? = null

    private external fun nativeSpotifyStart(context: Context, cachePath: String): Boolean
    private external fun nativeSpotifyStop()

    companion object {
        const val ACTION_START = "com.swiftmusic.spotify.START_CONNECT"
        const val ACTION_STOP = "com.swiftmusic.spotify.STOP_CONNECT"
        private const val CHANNEL_ID = "spotify_connect"
        private const val NOTIFICATION_ID = 7402

        init {
            try {
                System.loadLibrary("swift_spotify_connect")
            } catch (_: UnsatisfiedLinkError) { }
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        startForeground(NOTIFICATION_ID, notification())
        if (multicastLock?.isHeld != true) {
            val wifi = getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicastLock = wifi.createMulticastLock("swift_music_spotify_connect").apply {
                setReferenceCounted(false)
                acquire()
            }
        }
        try {
            nativeSpotifyStart(applicationContext, filesDir.resolve("spotify-connect").absolutePath)
        } catch (_: UnsatisfiedLinkError) {
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun notification(): Notification {
        val openApp = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle("Swift Music · Spotify Connect")
            .setContentText("Siap menerima pemutaran dari Spotify")
            .setContentIntent(openApp)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setOngoing(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Spotify Connect", NotificationManager.IMPORTANCE_LOW),
            )
        }
    }

    override fun onDestroy() {
        try { nativeSpotifyStop() } catch (_: UnsatisfiedLinkError) { }
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
