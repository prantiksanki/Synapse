package com.example.sign_language_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telephony.TelephonyManager
import io.flutter.plugin.common.EventChannel

/**
 * Listens for phone call state changes and forwards events to Flutter via
 * an [EventChannel] sink.
 *
 * Events sent as Map<String, Any>:
 *   { "event": "ringing" | "active" | "ended" | "tts_done", "number": "" }
 *
 * Design notes:
 * - Queues the last event if Flutter hasn't subscribed yet (sink is null).
 *   On [onListen], flushes the queue so no events are lost.
 * - Does NOT read EXTRA_INCOMING_NUMBER (requires READ_CALL_LOG on API 29+).
 * - Holds a weak reference to [MainActivity] to call [bringToFront] when
 *   the call is answered (OFFHOOK), pulling the app back in front of the
 *   Phone app UI.
 */
class CallStateReceiver : BroadcastReceiver(), EventChannel.StreamHandler {

    private var eventSink: EventChannel.EventSink? = null
    private var lastState = TelephonyManager.CALL_STATE_IDLE

    // Holds events that arrived before Flutter subscribed
    private val pendingEvents = mutableListOf<Map<String, String>>()

    /** Set by MainActivity; cleared in onDestroy to avoid leaks. */
    var mainActivity: MainActivity? = null

    // ── EventChannel.StreamHandler ──────────────────────────────────────────

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        // Flush any events that arrived before Flutter was listening
        pendingEvents.forEach { events?.success(it) }
        pendingEvents.clear()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // ── BroadcastReceiver ───────────────────────────────────────────────────

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return

        val stateStr = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
        android.util.Log.d("SYNAPSE_CallReceiver", "Phone state changed: $stateStr")

        val newState = when (stateStr) {
            TelephonyManager.EXTRA_STATE_RINGING  -> TelephonyManager.CALL_STATE_RINGING
            TelephonyManager.EXTRA_STATE_OFFHOOK  -> TelephonyManager.CALL_STATE_OFFHOOK
            TelephonyManager.EXTRA_STATE_IDLE     -> TelephonyManager.CALL_STATE_IDLE
            else -> return
        }

        if (newState == lastState) return
        lastState = newState

        val eventName = when (newState) {
            TelephonyManager.CALL_STATE_RINGING  -> "ringing"
            TelephonyManager.CALL_STATE_OFFHOOK  -> "active"
            TelephonyManager.CALL_STATE_IDLE     -> "ended"
            else -> return
        }

        android.util.Log.d("SYNAPSE_CallReceiver", "Sending event: $eventName")
        // Navigation is now handled by the floating bubble in CallTranslationService.
        // The user taps the bubble to open SYNAPSE — we no longer force the app to front.

        send(mapOf("event" to eventName, "number" to ""))
    }

    /** Called by [SynapseCallService] after TTS finishes so Flutter re-engages STT. */
    fun sendTtsDone() {
        android.util.Log.d("SYNAPSE_CallReceiver", "Sending tts_done event")
        send(mapOf("event" to "tts_done", "number" to ""))
    }

    /**
     * Called by MainActivity.onResume to re-sync call state after app restart.
     * Only sends if the state has actually changed (avoids duplicate events).
     */
    fun sendCurrentState(eventName: String) {
        android.util.Log.d("SYNAPSE_CallReceiver", "sendCurrentState: $eventName")
        send(mapOf("event" to eventName, "number" to ""))
    }

    private fun send(payload: Map<String, String>) {
        val sink = eventSink
        if (sink != null) {
            android.util.Log.d("SYNAPSE_CallReceiver", "Event sent to Flutter: $payload")
            sink.success(payload)
        } else {
            // Flutter hasn't subscribed yet — queue it
            android.util.Log.d("SYNAPSE_CallReceiver", "Flutter not listening yet - queuing: $payload")
            pendingEvents.add(payload)
        }
    }
}
