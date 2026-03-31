package com.example.sign_language_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat
import java.io.OutputStream
import kotlin.math.sqrt

/**
 * Foreground service for system-audio watch mode.
 *
 * Important:
 * - AudioPlaybackCapture works only on Android 10+ and only for apps that
 *   allow playback capture.
 * - Direct speech recognition from an external audio stream requires
 *   SpeechRecognizer audio-source support, which is realistically Android 13+.
 */
class SystemAudioCaptureService : Service() {

    companion object {
        private const val TAG = "SYNAPSE_WatchService"
        private const val NOTIFICATION_ID = 1002
        private const val CHANNEL_ID = "synapse_watch_channel"

        const val ACTION_START = "com.example.sign_language_app.WATCH_START"
        const val ACTION_STOP = "com.example.sign_language_app.WATCH_STOP"

        private const val SAMPLE_RATE = 16000
        private const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        private const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
        private const val SILENCE_RMS_THRESHOLD = 50.0
        private const val SILENCE_CHUNK_LIMIT = 20

        var eventBridge: WatchEventBridge? = null
    }

    private lateinit var notificationManager: NotificationManager
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())

    private var mediaProjection: MediaProjection? = null
    private var audioRecord: AudioRecord? = null
    private var captureThread: Thread? = null
    private var speechRecognizer: SpeechRecognizer? = null

    private var speechInputRead: ParcelFileDescriptor? = null
    private var speechInputWrite: ParcelFileDescriptor? = null
    private var speechInputStream: OutputStream? = null

    @Volatile
    private var running = false
    private var silentChunks = 0
    private var silenceWarningEmitted = false

    override fun onCreate() {
        super.onCreate()
        notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val resultCode = intent.getIntExtra("result_code", -1)
                    @Suppress("DEPRECATION")
                    val data = intent.getParcelableExtra<Intent>("data")
                    if (resultCode != -1 && data != null) {
                        startCapture(resultCode, data)
                    } else {
                        emitError("Invalid screen capture session.")
                        stopSelf()
                    }
                } else {
                    emitError("Watch mode requires Android 10 or newer.")
                    stopSelf()
                }
            }

            ACTION_STOP -> stopCapture()
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopCapture()
        super.onDestroy()
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun startCapture(resultCode: Int, data: Intent) {
        if (running) return

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            emitError("Watch mode transcription requires Android 13+.")
            stopSelf()
            return
        }

        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            emitError("Speech recognition is not available on this device.")
            stopSelf()
            return
        }

        startForeground(NOTIFICATION_ID, buildNotification())

        val mpManager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        mediaProjection = mpManager.getMediaProjection(resultCode, data)

        val projection = mediaProjection
        if (projection == null) {
            emitError("Failed to obtain screen capture session.")
            stopSelf()
            return
        }

        val captureConfig = AudioPlaybackCaptureConfiguration.Builder(projection)
            .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
            .addMatchingUsage(AudioAttributes.USAGE_GAME)
            .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
            .build()

        val bufferSize = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT)
            .coerceAtLeast(4096)

        audioRecord = AudioRecord.Builder()
            .setAudioPlaybackCaptureConfig(captureConfig)
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(SAMPLE_RATE)
                    .setChannelMask(CHANNEL_CONFIG)
                    .setEncoding(AUDIO_FORMAT)
                    .build()
            )
            .setBufferSizeInBytes(bufferSize * 4)
            .build()

        if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
            emitError("Audio capture could not be initialized.")
            stopSelf()
            return
        }

        try {
            startSpeechRecognitionSession()
        } catch (e: Exception) {
            emitError("Speech recognizer setup failed: ${e.message}")
            stopSelf()
            return
        }

        running = true
        silentChunks = 0
        silenceWarningEmitted = false

        audioRecord?.startRecording()
        emitStatus("capturing")

        captureThread = Thread { captureLoop(bufferSize) }.apply {
            name = "SynapseWatchCapture"
            isDaemon = true
            start()
        }
    }

    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    private fun startSpeechRecognitionSession() {
        // Create the pipe once — the write end stays open for the entire session.
        // Each recognition cycle reads from the same pipe; we only recreate the
        // SpeechRecognizer instance on each restart.
        val pipe = ParcelFileDescriptor.createPipe()
        speechInputRead = pipe[0]
        speechInputWrite = pipe[1]
        speechInputStream = ParcelFileDescriptor.AutoCloseOutputStream(speechInputWrite)

        mainHandler.post { startNextRecognitionCycle() }
    }

    /**
     * Creates a fresh SpeechRecognizer and starts one recognition session.
     * Must be called on the main thread (SpeechRecognizer requirement).
     * When the session ends (onResults or recoverable onError) we call this
     * again so recognition runs continuously for the entire watch session.
     */
    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    private fun startNextRecognitionCycle() {
        if (!running) return

        try {
            speechRecognizer?.destroy()
            speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this).apply {
                setRecognitionListener(object : RecognitionListener {
                    override fun onReadyForSpeech(params: android.os.Bundle?) {}
                    override fun onBeginningOfSpeech() {}
                    override fun onRmsChanged(rmsdB: Float) {}
                    override fun onBufferReceived(buffer: ByteArray?) {}
                    override fun onEndOfSpeech() {}
                    override fun onEvent(eventType: Int, params: android.os.Bundle?) {}

                    override fun onPartialResults(partialResults: android.os.Bundle?) {
                        val text = partialResults
                            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                            ?.firstOrNull()
                            .orEmpty()
                        if (text.isNotBlank()) {
                            eventBridge?.send(
                                mapOf(
                                    "event" to "transcript",
                                    "text" to text,
                                    "isFinal" to false,
                                ),
                            )
                        }
                    }

                    override fun onResults(results: android.os.Bundle?) {
                        val text = results
                            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                            ?.firstOrNull()
                            .orEmpty()
                        if (text.isNotBlank()) {
                            eventBridge?.send(
                                mapOf(
                                    "event" to "transcript",
                                    "text" to text,
                                    "isFinal" to true,
                                ),
                            )
                        }
                        // Session ended naturally — immediately start the next cycle
                        if (running) mainHandler.postDelayed({ startNextRecognitionCycle() }, 150)
                    }

                    override fun onError(error: Int) {
                        Log.w(TAG, "Speech recognizer error code: $error")
                        if (!running) return

                        when (error) {
                            // Transient errors — just restart after a short delay
                            SpeechRecognizer.ERROR_NO_MATCH,
                            SpeechRecognizer.ERROR_SPEECH_TIMEOUT,
                            SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> {
                                mainHandler.postDelayed({ startNextRecognitionCycle() }, 300)
                            }
                            // Audio source errors — pipe may be dead; stop the session
                            SpeechRecognizer.ERROR_AUDIO,
                            SpeechRecognizer.ERROR_SERVER,
                            SpeechRecognizer.ERROR_NETWORK,
                            SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> {
                                emitError("Speech recognizer error: $error")
                            }
                            // Anything else — attempt a single restart
                            else -> {
                                mainHandler.postDelayed({ startNextRecognitionCycle() }, 500)
                            }
                        }
                    }
                })
            }

            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(
                    RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
                )
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, speechInputRead)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AUDIO_FORMAT)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, SAMPLE_RATE)
                putExtra(
                    RecognizerIntent.EXTRA_SEGMENTED_SESSION,
                    RecognizerIntent.EXTRA_AUDIO_SOURCE,
                )
            }
            speechRecognizer?.startListening(intent)
        } catch (e: Exception) {
            Log.e(TAG, "startNextRecognitionCycle failed: ${e.message}")
            if (running) mainHandler.postDelayed({ startNextRecognitionCycle() }, 1000)
        }
    }

    private fun captureLoop(bufferSize: Int) {
        val shortChunk = ShortArray(bufferSize / 2)

        while (running) {
            val read = audioRecord?.read(shortChunk, 0, shortChunk.size) ?: break
            if (read <= 0) continue

            val rms = computeRms(shortChunk, read)
            if (rms < SILENCE_RMS_THRESHOLD) {
                silentChunks++
                if (silentChunks >= SILENCE_CHUNK_LIMIT && !silenceWarningEmitted) {
                    silenceWarningEmitted = true
                    emitStatus("silence")
                }
            } else {
                silentChunks = 0
                if (silenceWarningEmitted) {
                    silenceWarningEmitted = false
                    emitStatus("capturing")
                }
            }

            try {
                speechInputStream?.write(shortsToBytes(shortChunk, read))
                speechInputStream?.flush()
            } catch (e: Exception) {
                if (running) {
                    emitError("Audio stream pipe failed: ${e.message}")
                }
                break
            }
        }
    }

    private fun stopCapture() {
        val wasRunning = running
        running = false

        // Cancel any pending startNextRecognitionCycle() callbacks
        mainHandler.removeCallbacksAndMessages(null)

        try {
            captureThread?.interrupt()
        } catch (_: Exception) {}
        captureThread = null

        try {
            audioRecord?.stop()
        } catch (_: Exception) {}
        try {
            audioRecord?.release()
        } catch (_: Exception) {}
        audioRecord = null

        try {
            speechInputStream?.close()
        } catch (_: Exception) {}
        speechInputStream = null

        try {
            speechInputRead?.close()
        } catch (_: Exception) {}
        speechInputRead = null

        try {
            speechInputWrite?.close()
        } catch (_: Exception) {}
        speechInputWrite = null

        mainHandler.post {
            try {
                speechRecognizer?.cancel()
            } catch (_: Exception) {}
            try {
                speechRecognizer?.destroy()
            } catch (_: Exception) {}
            speechRecognizer = null
        }

        try {
            mediaProjection?.stop()
        } catch (_: Exception) {}
        mediaProjection = null

        if (wasRunning) {
            emitStatus("stopped")
        }
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun computeRms(shorts: ShortArray, count: Int): Double {
        var sum = 0.0
        for (i in 0 until count) {
            sum += shorts[i].toDouble() * shorts[i].toDouble()
        }
        return sqrt(sum / count)
    }

    private fun shortsToBytes(shorts: ShortArray, count: Int): ByteArray {
        val bytes = ByteArray(count * 2)
        for (i in 0 until count) {
            bytes[i * 2] = (shorts[i].toInt() and 0xFF).toByte()
            bytes[i * 2 + 1] = (shorts[i].toInt() shr 8 and 0xFF).toByte()
        }
        return bytes
    }

    private fun emitStatus(value: String) {
        eventBridge?.send(mapOf("event" to "status", "value" to value))
    }

    private fun emitError(message: String) {
        Log.e(TAG, message)
        eventBridge?.send(mapOf("event" to "error", "message" to message))
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "VAANI Watch Mode",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Active while translating supported video audio into sign output"
                setShowBadge(false)
            }
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntentFlags =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("VAANI Watching")
            .setContentText("Listening for capturable video audio")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setContentIntent(
                PendingIntent.getActivity(this, 0, launchIntent, pendingIntentFlags),
            )
            .setAutoCancel(false)
            .build()
    }
}
