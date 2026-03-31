package com.example.sign_language_app

import io.flutter.plugin.common.EventChannel

/**
 * Lightweight EventChannel.StreamHandler that bridges Kotlin events to Flutter
 * for the Watch Video feature.
 *
 * Events sent as Map<String, Any>:
 *   { "event": "projection_granted" }
 *   { "event": "projection_denied" }
 *   { "event": "transcript", "text": "...", "isFinal": true }
 *   { "event": "status", "value": "capturing" | "silence" | "stopped" }
 *   { "event": "error", "message": "..." }
 *
 * Design mirrors CallStateReceiver: queues events that arrive before Flutter
 * subscribes, then flushes them on onListen.
 */
class WatchEventBridge : EventChannel.StreamHandler {

    private var eventSink: EventChannel.EventSink? = null
    private val pendingEvents = mutableListOf<Map<String, Any>>()

    // ── EventChannel.StreamHandler ───────────────────────────────────────────

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        pendingEvents.forEach { events?.success(it) }
        pendingEvents.clear()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // ── Public API ───────────────────────────────────────────────────────────

    fun send(payload: Map<String, Any>) {
        val sink = eventSink
        if (sink != null) {
            sink.success(payload)
        } else {
            pendingEvents.add(payload)
        }
    }

    fun sendError(code: String, message: String) {
        val sink = eventSink
        if (sink != null) {
            sink.error(code, message, null)
        } else {
            pendingEvents.add(mapOf("event" to "error", "message" to message))
        }
    }
}
