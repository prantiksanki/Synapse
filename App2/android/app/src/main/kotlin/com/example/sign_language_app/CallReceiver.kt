package com.example.sign_language_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telephony.TelephonyManager
import android.util.Log

/**
 * BroadcastReceiver that detects phone call state changes and starts the
 * CallTranslationService. This receiver ONLY detects calls and starts services -
 * it does NOT launch activities or show UI directly (to avoid MIUI crashes).
 */
class CallReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "SYNAPSE_CallReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return

        val stateStr = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
        Log.d(TAG, "Phone state changed: $stateStr")

        when (stateStr) {
            TelephonyManager.EXTRA_STATE_RINGING -> {
                Log.d(TAG, "Call ringing - starting CallTranslationService")
                val serviceIntent = Intent(context, CallTranslationService::class.java).apply {
                    action = CallTranslationService.ACTION_CALL_RINGING
                }
                context.startForegroundService(serviceIntent)
            }
            TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                Log.d(TAG, "Call answered - notifying service")
                val serviceIntent = Intent(context, CallTranslationService::class.java).apply {
                    action = CallTranslationService.ACTION_CALL_ANSWERED
                }
                context.startForegroundService(serviceIntent)
            }
            TelephonyManager.EXTRA_STATE_IDLE -> {
                Log.d(TAG, "Call ended - stopping service")
                val serviceIntent = Intent(context, CallTranslationService::class.java).apply {
                    action = CallTranslationService.ACTION_CALL_ENDED
                }
                context.startService(serviceIntent) // Regular start, not foreground
            }
        }
    }
}