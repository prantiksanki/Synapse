package com.example.sign_language_app

import android.content.Intent
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.telephony.TelephonyManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    // ── Channel names ────────────────────────────────────────────────────────
    private val ttsChannelName    = "synapse/llm"
    private val callControlChannel = "synapse/call_control"
    private val callEventsChannel  = "synapse/call_events"
    private val audioUtilsChannel  = "synapse/audio_utils"

    // TTS service (existing, unchanged)
    private lateinit var ttsService: SynapseTtsService

    // Call state receiver — forwards phone state to Flutter via EventChannel
    private val callReceiver = CallStateReceiver()

    // Saved volume levels for mute/unmute
    private var savedNotificationVolume = -1
    private var savedSystemVolume       = -1
    private var savedRingVolume         = -1

    // ── FlutterEngine setup ──────────────────────────────────────────────────

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Show app over lock screen and turn screen on when a call arrives
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }

        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager

        // ── TTS channel (unchanged) ──────────────────────────────────────────
        ttsService = SynapseTtsService(this)
        MethodChannel(messenger, ttsChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "speak" -> {
                        val text = call.argument<String>("text").orEmpty()
                        ttsService.speak(text)
                        result.success(null)
                    }
                    "stopSpeaking" -> {
                        ttsService.stop()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Audio utils channel — mute/unmute STT beep sounds ────────────────
        MethodChannel(messenger, audioUtilsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "muteBeep" -> {
                        savedNotificationVolume =
                            audioManager.getStreamVolume(AudioManager.STREAM_NOTIFICATION)
                        savedSystemVolume =
                            audioManager.getStreamVolume(AudioManager.STREAM_SYSTEM)
                        savedRingVolume =
                            audioManager.getStreamVolume(AudioManager.STREAM_RING)
                        audioManager.setStreamVolume(
                            AudioManager.STREAM_NOTIFICATION, 0,
                            AudioManager.FLAG_REMOVE_SOUND_AND_VIBRATE
                        )
                        audioManager.setStreamVolume(
                            AudioManager.STREAM_SYSTEM, 0,
                            AudioManager.FLAG_REMOVE_SOUND_AND_VIBRATE
                        )
                        audioManager.setStreamVolume(
                            AudioManager.STREAM_RING, 0,
                            AudioManager.FLAG_REMOVE_SOUND_AND_VIBRATE
                        )
                        result.success(null)
                    }
                    "unmuteBeep" -> {
                        if (savedNotificationVolume >= 0) {
                            audioManager.setStreamVolume(
                                AudioManager.STREAM_NOTIFICATION, savedNotificationVolume, 0
                            )
                            savedNotificationVolume = -1
                        }
                        if (savedSystemVolume >= 0) {
                            audioManager.setStreamVolume(
                                AudioManager.STREAM_SYSTEM, savedSystemVolume, 0
                            )
                            savedSystemVolume = -1
                        }
                        if (savedRingVolume >= 0) {
                            audioManager.setStreamVolume(
                                AudioManager.STREAM_RING, savedRingVolume, 0
                            )
                            savedRingVolume = -1
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Call events stream — phone state → Flutter ───────────────────────
        // callReceiver acts as both BroadcastReceiver (registered in onResume)
        // and EventChannel.StreamHandler.
        callReceiver.mainActivity = this
        EventChannel(messenger, callEventsChannel)
            .setStreamHandler(callReceiver)

        // ── Call control channel — Flutter → native ──────────────────────────
        MethodChannel(messenger, callControlChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestOverlayPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                            !Settings.canDrawOverlays(this)) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            )
                            startActivity(intent)
                        }
                        result.success(null)
                    }
                    "startCallMode" -> {
                        // Service is started automatically by CallReceiver BroadcastReceiver.
                        // Nothing extra needed here.
                        result.success(null)
                    }
                    "stopCallMode" -> {
                        val stopIntent = Intent(this, CallTranslationService::class.java).apply {
                            action = CallTranslationService.ACTION_STOP_SERVICE
                        }
                        startService(stopIntent)
                        result.success(null)
                    }
                    "routeForTts" -> {
                        val intent = Intent(this, CallTranslationService::class.java).apply {
                            action = CallTranslationService.ACTION_ROUTE_FOR_TTS
                        }
                        startService(intent)
                        result.success(null)
                    }
                    "routeForStt" -> {
                        val intent = Intent(this, CallTranslationService::class.java).apply {
                            action = CallTranslationService.ACTION_ROUTE_FOR_STT
                        }
                        startService(intent)
                        result.success(null)
                    }
                    "speakForCall" -> {
                        val text = call.argument<String>("text").orEmpty()
                        // Speaker relay: keep the loudspeaker enabled so the
                        // phone microphone can send SYNAPSE speech into the call.
                        try {
                            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                            @Suppress("DEPRECATION")
                            audioManager.isSpeakerphoneOn = true
                        } catch (e: Exception) {
                            android.util.Log.w("SYNAPSE", "speakForCall audio setup: ${e.message}")
                        }
                        ttsService.speakForCall(text) {
                            // TTS done — stay in speaker relay mode so caller
                            // audio continues to reach the local microphone.
                            try {
                                audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                                @Suppress("DEPRECATION")
                                audioManager.isSpeakerphoneOn = true
                            } catch (e: Exception) {
                                android.util.Log.w("SYNAPSE", "speakForCall audio restore: ${e.message}")
                            }
                            // Notify Flutter via the events channel
                            callReceiver.sendTtsDone()
                        }
                        result.success(null)
                    }
                    "stopSpeaking" -> {
                        ttsService.stop()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ── Bring app to foreground (called by CallStateReceiver on OFFHOOK) ──────

    fun bringToFront() {
        try {
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                action = CallTranslationService.ACTION_CALL_ANSWERED
            }
            startActivity(intent)
        } catch (e: Exception) {
            android.util.Log.w("SYNAPSE", "bringToFront failed: ${e.message}")
        }
    }

    // ── Register/unregister BroadcastReceiver ─────────────────────────────────

    override fun onResume() {
        super.onResume()
        try {
            val filter = android.content.IntentFilter(
                android.telephony.TelephonyManager.ACTION_PHONE_STATE_CHANGED
            )
            androidx.core.content.ContextCompat.registerReceiver(
                this,
                callReceiver,
                filter,
                androidx.core.content.ContextCompat.RECEIVER_EXPORTED
            )
        } catch (_: Exception) {}

        // If the app was killed and restarted mid-call, Flutter needs to know
        // the current call state. Query telephony and inject the event.
        try {
            val tm = getSystemService(TELEPHONY_SERVICE) as TelephonyManager
            @Suppress("DEPRECATION")
            val state = tm.callState
            if (state == TelephonyManager.CALL_STATE_OFFHOOK) {
                callReceiver.sendCurrentState("active")
            } else if (state == TelephonyManager.CALL_STATE_RINGING) {
                callReceiver.sendCurrentState("ringing")
            }
        } catch (_: Exception) {}
    }

    override fun onPause() {
        super.onPause()
        try { unregisterReceiver(callReceiver) } catch (_: Exception) {}
    }

    // ── Activity lifecycle ────────────────────────────────────────────────────

    override fun onDestroy() {
        callReceiver.mainActivity = null
        if (::ttsService.isInitialized) ttsService.shutdown()
        super.onDestroy()
    }
}
