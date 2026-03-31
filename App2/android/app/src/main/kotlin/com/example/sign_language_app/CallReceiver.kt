package com.example.sign_language_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telephony.TelephonyManager
import android.util.Log

/**
 * Static BroadcastReceiver (registered in manifest) that detects phone call
 * state changes and starts/stops CallTranslationService.
 *
 * This receiver ONLY starts/stops the service — it does NOT touch Flutter
 * channels or launch activities directly (avoids crashes on MIUI).
 *
 * All service starts are wrapped in try/catch so any Android background-start
 * restriction on API 31+ logs a warning instead of crashing the app.
 */
class CallReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "SYNAPSE_CallReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return

        val stateStr = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
        Log.d(TAG, "Phone state: $stateStr")

        when (stateStr) {
            TelephonyManager.EXTRA_STATE_RINGING -> {
                Log.d(TAG, "Ringing — starting CallTranslationService")
                try {
                    val si = Intent(context, CallTranslationService::class.java).apply {
                        action = CallTranslationService.ACTION_CALL_RINGING
                    }
                    context.startForegroundService(si)
                } catch (e: Exception) {
                    Log.e(TAG, "Could not start service on RINGING: ${e.message}")
                }
            }
            TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                Log.d(TAG, "Answered — notifying CallTranslationService")
                try {
                    val si = Intent(context, CallTranslationService::class.java).apply {
                        action = CallTranslationService.ACTION_CALL_ANSWERED
                    }
                    context.startForegroundService(si)
                } catch (e: Exception) {
                    Log.e(TAG, "Could not start service on OFFHOOK: ${e.message}")
                }
            }
            TelephonyManager.EXTRA_STATE_IDLE -> {
                Log.d(TAG, "Idle — stopping CallTranslationService")
                try {
                    val si = Intent(context, CallTranslationService::class.java).apply {
                        action = CallTranslationService.ACTION_CALL_ENDED
                    }
                    context.startService(si)
                } catch (e: Exception) {
                    Log.e(TAG, "Could not stop service on IDLE: ${e.message}")
                }
            }
        }
    }
}
