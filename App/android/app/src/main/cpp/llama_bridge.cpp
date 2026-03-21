/**
 * llama_bridge.cpp — JNI bridge between Kotlin LlamaService and llama.cpp.
 *
 * -------------------------------------------------------------------------
 * CURRENT STATE: STUB IMPLEMENTATION
 * -------------------------------------------------------------------------
 * The functions below are intentional stubs so that SYNAPSE compiles and
 * runs on-device without a full llama.cpp build.
 *
 * HOW TO REPLACE STUBS WITH REAL llama.cpp INFERENCE:
 * -------------------------------------------------------------------------
 *  1. Clone llama.cpp into the cpp/ directory alongside this file:
 *       git clone https://github.com/ggerganov/llama.cpp
 *
 *  2. Update CMakeLists.txt:
 *       add_subdirectory(llama.cpp)
 *       # Then link: target_link_libraries(llama_bridge llama ...)
 *
 *  3. In nativeLoadModel:
 *       llama_backend_init(false);
 *       llama_model_params mparams = llama_model_default_params();
 *       llama_model* model = llama_load_model_from_file(path, mparams);
 *       llama_context_params cparams = llama_context_default_params();
 *       cparams.n_ctx = 512;
 *       llama_context* ctx = llama_new_context_with_model(model, cparams);
 *       return (jlong)(uintptr_t)ctx;
 *
 *  4. In nativeGenerate:
 *       Use llama_tokenize + llama_decode + llama_token_to_piece for a full
 *       generation loop (greedy or temperature sampling).
 *
 *  5. In nativeFreeModel:
 *       llama_context* ctx = (llama_context*)(uintptr_t)contextPtr;
 *       llama_free(ctx);
 *       llama_backend_free();
 *
 * Reference: https://github.com/ggerganov/llama.cpp/blob/master/examples/simple/simple.cpp
 * -------------------------------------------------------------------------
 */

#include <jni.h>
#include <string>
#include <android/log.h>

#define LOG_TAG "llama_bridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

extern "C" {

/**
 * Load a GGUF model from the given file path.
 *
 * Stub: Returns a non-zero sentinel (1) so Kotlin treats it as "loaded".
 * Replace with real llama_load_model_from_file() + llama_new_context_with_model().
 *
 * @param path  Absolute path to the .gguf model file on device storage.
 * @return      Opaque context pointer (cast to jlong); 0 indicates failure.
 */
JNIEXPORT jlong JNICALL
Java_com_synapse_app_LlamaService_nativeLoadModel(
        JNIEnv* env,
        jobject /* this */,
        jstring path) {

    const char* modelPath = env->GetStringUTFChars(path, nullptr);
    LOGI("nativeLoadModel (stub): path=%s", modelPath);
    env->ReleaseStringUTFChars(path, modelPath);

    // TODO: Replace with real llama.cpp context creation.
    // Return 1 as a placeholder non-null pointer.
    return static_cast<jlong>(1);
}

/**
 * Run text generation for a given prompt.
 *
 * Stub: Returns the prompt text unchanged so the UI pipeline can be tested
 * end-to-end without a real model. Replace with a proper llama.cpp decode loop.
 *
 * @param contextPtr  Value returned by nativeLoadModel.
 * @param prompt      Full instruction-formatted prompt string.
 * @return            Generated text (or echo of prompt for stub).
 */
JNIEXPORT jstring JNICALL
Java_com_synapse_app_LlamaService_nativeGenerate(
        JNIEnv* env,
        jobject /* this */,
        jlong   contextPtr,
        jstring prompt) {

    const char* promptStr = env->GetStringUTFChars(prompt, nullptr);
    LOGI("nativeGenerate (stub): ctx=%lld, prompt_len=%zu", (long long)contextPtr, strlen(promptStr));

    // TODO: Replace with real llama.cpp tokenize → decode → detokenize loop.
    // For now, build a placeholder sentence from the last line of the prompt.
    std::string input(promptStr);
    env->ReleaseStringUTFChars(prompt, promptStr);

    // Extract the keyword portion from the prompt for a meaningful stub response
    std::string stubResponse = "[Model not loaded] " + input.substr(0, 80);

    return env->NewStringUTF(stubResponse.c_str());
}

/**
 * Free all native resources associated with the given context pointer.
 *
 * Stub: No-op. Replace with llama_free(ctx) and llama_backend_free().
 *
 * @param contextPtr  Value returned by nativeLoadModel.
 */
JNIEXPORT void JNICALL
Java_com_synapse_app_LlamaService_nativeFreeModel(
        JNIEnv* /* env */,
        jobject /* this */,
        jlong   contextPtr) {

    LOGI("nativeFreeModel (stub): ctx=%lld — nothing to free in stub mode.", (long long)contextPtr);
    // TODO: Replace with:
    //   llama_context* ctx = reinterpret_cast<llama_context*>(contextPtr);
    //   llama_free(ctx);
    //   llama_backend_free();
}

} // extern "C"
