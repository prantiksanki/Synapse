package com.example.sign_language_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.media.AudioManager
import android.os.Binder
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Foreground service that keeps the call bridge alive while a phone call is active.
 *
 * Responsibilities:
 *  - Manage [AudioManager] mode for in-call audio routing.
 *  - Expose [speakForCall] to speak TTS into the call via USAGE_VOICE_COMMUNICATION.
 *  - Toggle speakerphone so STT can hear the caller's voice.
 *  - Notify Flutter when TTS is done so STT can re-engage.
 *  - Bring the Synapse app back to the foreground when the call is answered.
 */
class SynapseCallService : Service() {

    companion object {
        private const val CHANNEL_ID      = "synapse_call_channel"
        private const val NOTIFICATION_ID = 1001
    }

    inner class CallBinder : Binder() {
        fun getService(): SynapseCallService = this@SynapseCallService
    }

    private val binder = CallBinder()
    private lateinit var audioManager: AudioManager
    private lateinit var ttsService: SynapseTtsService

    /** Set by MainActivity so TTS-done events reach Flutter. */
    var callStateReceiver: CallStateReceiver? = null

    override fun onCreate() {
        super.onCreate()
        android.util.Log.d("SYNAPSE_Call", "SynapseCallService.onCreate()")
        try {
            audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
            ttsService = SynapseTtsService(this)
            createNotificationChannel()
            startForeground(NOTIFICATION_ID, buildNotification(fullScreen = false))
        } catch (e: Exception) {
            android.util.Log.e("SYNAPSE_Call", "Error in onCreate: ${e.message}", e)
            throw e
        }
    }

    override fun onBind(intent: Intent): IBinder {
        android.util.Log.d("SYNAPSE_Call", "SynapseCallService.onBind()")
        return binder
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        android.util.Log.d("SYNAPSE_Call", "SynapseCallService.onStartCommand()")
        return START_STICKY
    }

    override fun onDestroy() {
        android.util.Log.d("SYNAPSE_Call", "SynapseCallService.onDestroy()")
        try {
            routeForNormal()
            ttsService.shutdown()
        } catch (e: Exception) {
            android.util.Log.e("SYNAPSE_Call", "Error in onDestroy: ${e.message}", e)
        }
        super.onDestroy()
    }

    // ── Bring app to foreground ──────────────────────────────────────────────

    /**
     * Called when the call transitions to OFFHOOK (accepted).
     * Fires a high-priority full-screen intent notification so Android brings
     * the Synapse app back over the Phone app UI.
     */
    fun bringAppToForeground() {
        android.util.Log.d("SYNAPSE_Call", "bringAppToForeground()")
        try {
            val nm = getSystemService(NotificationManager::class.java)
            nm.notify(NOTIFICATION_ID, buildNotification(fullScreen = true))
        } catch (e: Exception) {
            android.util.Log.e("SYNAPSE_Call", "Error in bringAppToForeground: ${e.message}", e)
        }
    }

    // ── Audio routing ────────────────────────────────────────────────────────

    /**
     * Enter in-call audio mode and enable speakerphone so the microphone can
     * pick up the caller's voice for STT.
     */
    fun routeForStt() {
        try {
            android.util.Log.d("SYNAPSE_Call", "routeForStt()")
            audioManager.mode = AudioManager.MODE_IN_CALL
            @Suppress("DEPRECATION")
            audioManager.isSpeakerphoneOn = true
        } catch (e: Exception) {
            android.util.Log.e("SYNAPSE_Call", "Error in routeForStt: ${e.message}", e)
        }
    }

    /**
     * Keep in-call mode but disable speakerphone before TTS speaks, preventing
     * the TTS output from looping back into the microphone.
     */
    fun routeForTts() {
        try {
            android.util.Log.d("SYNAPSE_Call", "routeForTts()")
            audioManager.mode = AudioManager.MODE_IN_CALL
            @Suppress("DEPRECATION")
            audioManager.isSpeakerphoneOn = false
        } catch (e: Exception) {
            android.util.Log.e("SYNAPSE_Call", "Error in routeForTts: ${e.message}", e)
        }
    }

    /** Restore normal audio mode (call ended). */
    fun routeForNormal() {
        try {
            android.util.Log.d("SYNAPSE_Call", "routeForNormal()")
            @Suppress("DEPRECATION")
            audioManager.isSpeakerphoneOn = false
            audioManager.mode = AudioManager.MODE_NORMAL
        } catch (e: Exception) {
            android.util.Log.e("SYNAPSE_Call", "Error in routeForNormal: ${e.message}", e)
        }
    }

    // ── TTS ──────────────────────────────────────────────────────────────────

    /**
     * Speak [text] into the active call.
     * Disables speakerphone while speaking (avoids echo), then re-enables it
     * and fires [callStateReceiver].sendTtsDone() so Flutter re-engages STT.
     */
    fun speakForCall(text: String) {
        android.util.Log.d("SYNAPSE_Call", "speakForCall: '$text'")
        try {
            routeForTts()
            ttsService.speakForCall(text) {
                // TTS finished — switch audio back to STT-listening mode
                android.util.Log.d("SYNAPSE_Call", "TTS done, routing back to STT")
                routeForStt()
                callStateReceiver?.sendTtsDone()
            }
        } catch (e: Exception) {
            android.util.Log.e("SYNAPSE_Call", "Error in speakForCall: ${e.message}", e)
            routeForStt()
            callStateReceiver?.sendTtsDone()
        }
    }

    fun stopSpeaking() {
        android.util.Log.d("SYNAPSE_Call", "stopSpeaking()")
        try {
            ttsService.stop()
            routeForStt()
        } catch (e: Exception) {
            android.util.Log.e("SYNAPSE_Call", "Error in stopSpeaking: ${e.message}", e)
        }
    }

    // ── Notification ─────────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "SYNAPSE Call Bridge",
                // HIGH importance is required for full-screen intent to work
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Active while a phone call is in progress"
                setShowBadge(false)
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(fullScreen: Boolean): Notification {
        // Intent that re-opens (or brings to front) MainActivity
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
            action = "SYNAPSE_CALL_ACTIVE"
        }
        val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else
            PendingIntent.FLAG_UPDATE_CURRENT

        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent, pendingFlags
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("SYNAPSE — Call Active")
            .setContentText("Tap to open sign language bridge")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setAutoCancel(false)

        if (fullScreen) {
            // Full-screen intent — Android will show the activity over the Phone app
            builder.setFullScreenIntent(pendingIntent, true)
        }

        return builder.build()
    }
}
