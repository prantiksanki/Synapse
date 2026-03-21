package com.synapse.app

import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * LlamaPlugin — Flutter MethodChannel bridge for local LLM inference.
 *
 * Exposes three methods to Dart via the channel "com.synapse.app/llama":
 *
 *   • loadModel(modelPath: String) → Boolean
 *     Load a GGUF model file from the given path.
 *
 *   • generateSentence(signWords: String) → String
 *     Convert space-separated sign-language keywords into a natural sentence.
 *
 *   • releaseModel() → void
 *     Free native resources held by the loaded model.
 *
 * All inference calls are dispatched to a dedicated single-thread executor
 * so they never block the Flutter UI thread.
 */
class LlamaPlugin(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {

    companion object {
        /** MethodChannel name — must match the Dart-side channel name. */
        const val CHANNEL_NAME = "com.synapse.app/llama"
        private const val TAG = "LlamaPlugin"
    }

    private val channel = MethodChannel(messenger, CHANNEL_NAME)

    /** Single-thread executor isolates native inference from the UI thread. */
    private val executor = Executors.newSingleThreadExecutor()

    /** Shared LlamaService instance managing native context lifecycle. */
    private val llamaService = LlamaService()

    init {
        channel.setMethodCallHandler(this)
        Log.i(TAG, "LlamaPlugin registered on channel: $CHANNEL_NAME")
    }

    // -------------------------------------------------------------------------
    // MethodChannel.MethodCallHandler implementation
    // -------------------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {

            "loadModel" -> {
                val modelPath = call.argument<String>("modelPath")
                if (modelPath.isNullOrBlank()) {
                    result.error("INVALID_ARGUMENT", "modelPath must not be null or empty.", null)
                    return
                }

                // Run model loading on background thread to avoid ANR
                executor.submit {
                    try {
                        val success = llamaService.loadModel(modelPath)
                        Log.i(TAG, "loadModel result: $success")
                        // Post back to Flutter's platform thread
                        result.success(success)
                    } catch (e: Exception) {
                        Log.e(TAG, "loadModel exception: ${e.message}")
                        result.error("LOAD_ERROR", e.message, null)
                    }
                }
            }

            "generateSentence" -> {
                val signWords = call.argument<String>("signWords")
                if (signWords.isNullOrBlank()) {
                    result.error("INVALID_ARGUMENT", "signWords must not be null or empty.", null)
                    return
                }

                if (!llamaService.isLoaded) {
                    // Return the raw keywords as a graceful fallback when no model is loaded
                    Log.w(TAG, "generateSentence called without a loaded model; echoing input.")
                    result.success(signWords)
                    return
                }

                // Inference is expensive — run on background thread
                executor.submit {
                    try {
                        val sentence = llamaService.generateSentence(signWords)
                        Log.d(TAG, "Generated: $sentence")
                        result.success(sentence)
                    } catch (e: Exception) {
                        Log.e(TAG, "generateSentence exception: ${e.message}")
                        result.error("INFERENCE_ERROR", e.message, null)
                    }
                }
            }

            "releaseModel" -> {
                executor.submit {
                    try {
                        llamaService.release()
                        Log.i(TAG, "Model released.")
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e(TAG, "releaseModel exception: ${e.message}")
                        result.error("RELEASE_ERROR", e.message, null)
                    }
                }
            }

            else -> {
                Log.w(TAG, "Unhandled method: ${call.method}")
                result.notImplemented()
            }
        }
    }
}
