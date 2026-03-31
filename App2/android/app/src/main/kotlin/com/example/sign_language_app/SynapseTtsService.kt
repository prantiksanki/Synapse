package com.example.sign_language_app

import android.content.Context
import android.media.AudioAttributes
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.util.Locale

class SynapseTtsService(context: Context) : TextToSpeech.OnInitListener {
    private val tts = TextToSpeech(context.applicationContext, this)
    private var isReady = false

    // Normal audio attributes (media stream — for regular app use)
    private val normalAttrs = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()

    // Speaker-relay audio attributes — routes TTS to the voice call audio path,
    // which plays through the loudspeaker when speakerphone is ON so the mic
    // can acoustically relay it into the WebRTC audio stream.
    private val callAttrs = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            tts.language = Locale.US
            tts.setAudioAttributes(normalAttrs)
            isReady = true
        }
    }

    /** Speak in normal (non-call) mode. */
    fun speak(text: String) {
        if (!isReady || text.isBlank()) return
        tts.setAudioAttributes(normalAttrs)
        tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, "synapse_sentence")
    }

    /**
     * Speak during an active phone call using speaker relay.
     * The speech is played through the device loudspeaker so the phone
     * microphone can acoustically relay it into the normal carrier call.
     * [onDone] is called when the utterance finishes or is interrupted.
     */
    fun speakForCall(text: String, onDone: () -> Unit) {
        if (!isReady || text.isBlank()) {
            android.util.Log.d("SYNAPSE_TTS", "speakForCall: not ready or blank text (ready=$isReady)")
            onDone()
            return
        }
        try {
            val utteranceId = "synapse_call_${System.currentTimeMillis()}"
            tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(id: String?) {
                    android.util.Log.d("SYNAPSE_TTS", "TTS onStart: $id")
                }
                override fun onDone(id: String?) {
                    if (id == utteranceId) {
                        android.util.Log.d("SYNAPSE_TTS", "TTS onDone: $id")
                        tts.setOnUtteranceProgressListener(null)
                        onDone()
                    }
                }
                @Deprecated("Deprecated in API 21", ReplaceWith("onError(utteranceId, errorCode)"))
                override fun onError(id: String?) {
                    if (id == utteranceId) {
                        android.util.Log.w("SYNAPSE_TTS", "TTS onError: $id")
                        tts.setOnUtteranceProgressListener(null)
                        onDone()
                    }
                }

                override fun onError(utteranceId: String?, errorCode: Int) {
                    android.util.Log.w("SYNAPSE_TTS", "TTS error: $utteranceId, code=$errorCode")
                    tts.setOnUtteranceProgressListener(null)
                    onDone()
                }
            })
            tts.setAudioAttributes(callAttrs)
            tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, utteranceId)
            android.util.Log.d("SYNAPSE_TTS", "speakForCall started: $utteranceId")
        } catch (e: Exception) {
            android.util.Log.e("SYNAPSE_TTS", "Error in speakForCall: ${e.message}", e)
            onDone()
        }
    }

    fun stop() {
        if (isReady) {
            tts.stop()
            // Restore normal attributes after stopping
            tts.setAudioAttributes(normalAttrs)
        }
    }

    fun shutdown() {
        tts.stop()
        tts.shutdown()
    }
}
