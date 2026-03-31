package com.example.sign_language_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.graphics.PixelFormat
import android.media.AudioManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import kotlin.math.abs

/**
 * Foreground service that keeps SYNAPSE alive during phone calls.
 *
 * Responsibilities:
 *  1. Run as a foreground service so Android doesn't kill the process.
 *  2. Show a draggable floating SYNAPSE bubble on the phone call screen.
 *  3. Tap the bubble → open SYNAPSE (MainActivity with call panel).
 *  4. Manage acoustic speaker-relay routing for both STT and TTS.
 *  5. Remove the bubble and stop when the call ends.
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
        const val ACTION_ROUTE_FOR_TTS = "com.example.sign_language_app.ROUTE_FOR_TTS"
        const val ACTION_ROUTE_FOR_STT = "com.example.sign_language_app.ROUTE_FOR_STT"
    }

    private lateinit var audioManager: AudioManager
    private lateinit var notificationManager: NotificationManager

    // Floating bubble
    private var windowManager: WindowManager? = null
    private var bubbleView: View? = null

    // ── Lifecycle ─────────────────────────────────────────────────────────────

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
            ACTION_ROUTE_FOR_TTS -> routeForTts()
            ACTION_ROUTE_FOR_STT -> routeForStt()
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        Log.d(TAG, "onDestroy")
        removeBubble()
        restoreAudio()
        super.onDestroy()
    }

    // ── Call state handlers ───────────────────────────────────────────────────

    private fun handleRinging() {
        Log.d(TAG, "Call ringing — showing bubble")
        startForeground(NOTIFICATION_ID, buildNotification("Tap VAANI to translate call", fullScreen = false))
        showBubble()
        try { audioManager.mode = AudioManager.MODE_IN_COMMUNICATION } catch (e: Exception) {
            Log.w(TAG, "audio mode error: ${e.message}")
        }
    }

    private fun handleAnswered() {
        Log.d(TAG, "Call answered — enabling speaker relay")
        try {
            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            @Suppress("DEPRECATION")
            audioManager.isSpeakerphoneOn = true
        } catch (e: Exception) {
            Log.w(TAG, "audio route error: ${e.message}")
        }
        // Update notification — bubble still visible; user can tap it
        notificationManager.notify(NOTIFICATION_ID, buildNotification("Call active — tap bubble to translate", fullScreen = false))
    }

    private fun handleEnded() {
        Log.d(TAG, "Call ended — removing bubble")
        removeBubble()
        restoreAudio()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    // ── Floating bubble ───────────────────────────────────────────────────────

    private fun showBubble() {
        if (bubbleView != null) return

        // Overlay permission check (TYPE_APPLICATION_OVERLAY requires it on API 26+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            !android.provider.Settings.canDrawOverlays(this)) {
            Log.w(TAG, "Overlay permission not granted — skipping bubble")
            return
        }

        try {
            val wm = getSystemService(WINDOW_SERVICE) as WindowManager
            windowManager = wm

            val bubble = LayoutInflater.from(this).inflate(R.layout.synapse_bubble, null)

            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                x = 16
                y = 300
            }

            var initialX = 0
            var initialY = 0
            var touchX = 0f
            var touchY = 0f

            bubble.setOnTouchListener { _, event ->
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = params.x
                        initialY = params.y
                        touchX = event.rawX
                        touchY = event.rawY
                        true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        params.x = initialX + (event.rawX - touchX).toInt()
                        params.y = initialY + (event.rawY - touchY).toInt()
                        try { wm.updateViewLayout(bubble, params) } catch (_: Exception) {}
                        true
                    }
                    MotionEvent.ACTION_UP -> {
                        val dx = abs(event.rawX - touchX)
                        val dy = abs(event.rawY - touchY)
                        if (dx < 10 && dy < 10) {
                            // Tap (not drag) — open SYNAPSE
                            openSynapse()
                        }
                        true
                    }
                    else -> false
                }
            }

            wm.addView(bubble, params)
            bubbleView = bubble
            Log.d(TAG, "Bubble shown")
        } catch (e: Exception) {
            Log.e(TAG, "showBubble error: ${e.message}")
        }
    }

    private fun removeBubble() {
        bubbleView?.let { view ->
            try {
                windowManager?.removeView(view)
                Log.d(TAG, "Bubble removed")
            } catch (e: Exception) {
                Log.w(TAG, "removeBubble error: ${e.message}")
            }
            bubbleView = null
        }
    }

    private fun openSynapse() {
        Log.d(TAG, "Bubble tapped — opening SYNAPSE")
        try {
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                action = ACTION_CALL_ANSWERED
            }
            startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "openSynapse error: ${e.message}")
        }
    }

    // ── Audio helpers ─────────────────────────────────────────────────────────

    fun routeForTts() {
        try {
            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            @Suppress("DEPRECATION")
            audioManager.isSpeakerphoneOn = true
            Log.d(TAG, "routeForTts: speakerphone ON for acoustic relay")
        } catch (e: Exception) { Log.w(TAG, "routeForTts: ${e.message}") }
    }

    fun routeForStt() {
        try {
            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            @Suppress("DEPRECATION")
            audioManager.isSpeakerphoneOn = true
            Log.d(TAG, "routeForStt: speakerphone ON for caller relay capture")
        } catch (e: Exception) { Log.w(TAG, "routeForStt: ${e.message}") }
    }

    private fun restoreAudio() {
        try {
            @Suppress("DEPRECATION")
            audioManager.isSpeakerphoneOn = false
            audioManager.mode = AudioManager.MODE_NORMAL
        } catch (e: Exception) { Log.w(TAG, "restoreAudio: ${e.message}") }
    }

    // ── Notification ──────────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CHANNEL_ID, "VAANI Call Bridge", NotificationManager.IMPORTANCE_HIGH
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
            .setContentTitle("VAANI \u2014 Call Active")
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
