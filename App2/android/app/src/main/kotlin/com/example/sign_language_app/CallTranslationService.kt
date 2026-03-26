package com.example.sign_language_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.media.AudioManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Foreground service that keeps SYNAPSE alive during phone calls.
 * Gesture detection, STT, TTS, and UI all remain in Flutter/MainActivity.
 * This service only keeps the process alive and manages audio routing.
 */
class CallTranslationService : Service() {

    companion object {
        private const val TAG = "SYNAPSE_CallService"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "synapse_call_channel"

        const val ACTION_CALL_RINGING  = "com.example.sign_language_app.CALL_RINGING"
        const val ACTION_CALL_ANSWERED = "com.example.sign_language_app.CALL_ANSWERED"
        const val ACTION_CALL_ENDED    = "com.example.sign_language_app.CALL_ENDED"
        const val ACTION_STOP_SERVICE  = "com.example.sign_language_app.STOP_SERVICE"
    }

    private lateinit var audioManager: AudioManager
    private lateinit var notificationManager: NotificationManager

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "onCreate")
        audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
        notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand: ${intent?.action}")
        when (intent?.action) {
            ACTION_CALL_RINGING  -> handleRinging()
            ACTION_CALL_ANSWERED -> handleAnswered()
            ACTION_CALL_ENDED    -> handleEnded()
            ACTION_STOP_SERVICE  -> handleEnded()
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        Log.d(TAG, "onDestroy")
        restoreAudio()
        super.onDestroy()
    }

    private fun handleRinging() {
        Log.d(TAG, "Call ringing")
        startForeground(NOTIFICATION_ID, buildNotification("Incoming call\u2026", fullScreen = false))
        try { audioManager.mode = AudioManager.MODE_IN_CALL } catch (e: Exception) {
            Log.w(TAG, "audio mode error: ${e.message}")
        }
    }

    private fun handleAnswered() {
        Log.d(TAG, "Call answered")
        try {
            audioManager.mode = AudioManager.MODE_IN_CALL
            @Suppress("DEPRECATION")
            audioManager.isSpeakerphoneOn = true
        } catch (e: Exception) {
            Log.w(TAG, "audio route error: ${e.message}")
        }
        notificationManager.notify(NOTIFICATION_ID, buildNotification("Call active \u2014 translating", fullScreen = true))
        try {
            val launch = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                action = ACTION_CALL_ANSWERED
            }
            startActivity(launch)
        } catch (e: Exception) {
            Log.w(TAG, "launch MainActivity error: ${e.message}")
        }
    }

    private fun handleEnded() {
        Log.d(TAG, "Call ended")
        restoreAudio()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    fun routeForTts() {
        try {
            audioManager.mode = AudioManager.MODE_IN_CALL
            @Suppress("DEPRECATION")
            audioManager.isSpeakerphoneOn = false
        } catch (e: Exception) { Log.w(TAG, "routeForTts: ${e.message}") }
    }

    fun routeForStt() {
        try {
            audioManager.mode = AudioManager.MODE_IN_CALL
            @Suppress("DEPRECATION")
            audioManager.isSpeakerphoneOn = true
        } catch (e: Exception) { Log.w(TAG, "routeForStt: ${e.message}") }
    }

    private fun restoreAudio() {
        try {
            @Suppress("DEPRECATION")
            audioManager.isSpeakerphoneOn = false
            audioManager.mode = AudioManager.MODE_NORMAL
        } catch (e: Exception) { Log.w(TAG, "restoreAudio: ${e.message}") }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CHANNEL_ID, "SYNAPSE Call Bridge", NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Active while a phone call is in progress"
                setShowBadge(false)
            }
            notificationManager.createNotificationChannel(ch)
        }
    }

    private fun buildNotification(text: String, fullScreen: Boolean): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
            action = ACTION_CALL_ANSWERED
        }
        val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else PendingIntent.FLAG_UPDATE_CURRENT

        val pi = PendingIntent.getActivity(this, 0, launchIntent, piFlags)
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("SYNAPSE \u2014 Call Active")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setOngoing(true)
            .setContentIntent(pi)
            .setAutoCancel(false)
        if (fullScreen) builder.setFullScreenIntent(pi, true)
        return builder.build()
    }
}
