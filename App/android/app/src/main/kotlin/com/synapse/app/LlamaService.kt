package com.synapse.app

import android.util.Log

/**
 * LlamaService — Kotlin wrapper around the llama.cpp JNI bridge.
 *
 * Lifecycle:
 *   1. Call [loadModel] with the path to a GGUF model file.
 *   2. Call [generateSentence] one or more times with detected sign-language words.
 *   3. Call [release] when done to free native memory.
 *
 * The actual inference is performed in native C++ via llama_bridge.so.
 * The stub implementation returns echo responses so the app runs without
 * a real llama.cpp build; replace the native stubs with real llama.cpp calls
 * following the instructions in llama_bridge.cpp.
 */
class LlamaService {

    companion object {
        private const val TAG = "LlamaService"

        init {
            // Load the compiled native library (libllama_bridge.so)
            try {
                System.loadLibrary("llama_bridge")
                Log.i(TAG, "llama_bridge native library loaded successfully.")
            } catch (e: UnsatisfiedLinkError) {
                Log.e(TAG, "Failed to load llama_bridge: ${e.message}")
            }
        }
    }

    // -------------------------------------------------------------------------
    // JNI declarations — implemented in llama_bridge.cpp
    // -------------------------------------------------------------------------

    /**
     * Load a GGUF model from disk and return an opaque context pointer.
     * Returns 0 on failure.
     */
    external fun nativeLoadModel(path: String): Long

    /**
     * Run text generation against an already-loaded context.
     * [contextPtr] is the value returned by [nativeLoadModel].
     * Returns the generated text string.
     */
    external fun nativeGenerate(contextPtr: Long, prompt: String): String

    /**
     * Free native resources allocated by [nativeLoadModel].
     */
    external fun nativeFreeModel(contextPtr: Long)

    // -------------------------------------------------------------------------
    // Internal state
    // -------------------------------------------------------------------------

    /** Opaque pointer to the native llama_context; 0 means not loaded. */
    private var contextPtr: Long = 0L

    /** Whether a model is currently loaded and ready for inference. */
    var isLoaded: Boolean = false
        private set

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

    /**
     * Load the GGUF model at [modelPath] into native memory.
     * Must be called before [generateSentence].
     *
     * @return true if the model was loaded successfully.
     */
    fun loadModel(modelPath: String): Boolean {
        return try {
            Log.i(TAG, "Loading model from: $modelPath")
            contextPtr = nativeLoadModel(modelPath)
            isLoaded = contextPtr != 0L
            if (isLoaded) {
                Log.i(TAG, "Model loaded successfully (ctx=$contextPtr).")
            } else {
                Log.e(TAG, "nativeLoadModel returned 0 — model load failed.")
            }
            isLoaded
        } catch (e: Exception) {
            Log.e(TAG, "Exception while loading model: ${e.message}")
            isLoaded = false
            false
        }
    }

    /**
     * Convert detected sign-language keywords into a natural English sentence.
     *
     * Constructs an instruction-style prompt compatible with TinyLlama-Chat and
     * forwards it to the native inference engine.
     *
     * @param signWords Comma-separated sign keywords, e.g. "HELP PLEASE WATER"
     * @return Generated sentence, or a fallback string on error.
     */
    fun generateSentence(signWords: String): String {
        if (!isLoaded) {
            Log.w(TAG, "generateSentence called but model is not loaded.")
            return signWords // Echo back as fallback
        }

        // TinyLlama-Chat instruction format
        val prompt = buildString {
            append("<|system|>\n")
            append("You are a helpful assistant that converts sign language keywords ")
            append("into natural, grammatically correct English sentences.\n</s>\n")
            append("<|user|>\n")
            append("Convert these sign language keywords into a natural English sentence. ")
            append("Only output the sentence, nothing else.\n")
            append("Signs: $signWords\n</s>\n")
            append("<|assistant|>\n")
        }

        return try {
            Log.d(TAG, "Running inference for signs: $signWords")
            val result = nativeGenerate(contextPtr, prompt)
            Log.d(TAG, "Inference result: $result")
            result.trim().ifBlank { signWords }
        } catch (e: Exception) {
            Log.e(TAG, "Inference failed: ${e.message}")
            signWords
        }
    }

    /**
     * Release all native resources.
     * After calling this, [isLoaded] will be false and the service must be
     * re-initialized before further use.
     */
    fun release() {
        if (contextPtr != 0L) {
            try {
                nativeFreeModel(contextPtr)
                Log.i(TAG, "Native model context freed.")
            } catch (e: Exception) {
                Log.e(TAG, "Error freeing native context: ${e.message}")
            } finally {
                contextPtr = 0L
                isLoaded = false
            }
        }
    }
}
