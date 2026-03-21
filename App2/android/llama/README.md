# llama.cpp Scaffold

This directory is reserved for vendored `llama.cpp` sources for SYNAPSE.

Current state:
- Flutter talks to Android through the `synapse/llm` method channel.
- `LlamaService.kt` owns the local model lifecycle contract.
- The current native sentence path is a deterministic local fallback so the
  Flutter app can run end-to-end without bundling a remote dependency.

To replace the fallback with full `llama.cpp` inference later:
1. Vendor `llama.cpp` into this directory.
2. Add the JNI/CMake build under `android/app/src/main/cpp`.
3. Update `LlamaService.kt` to call the native bridge instead of
   `SentenceTemplateEngine`.
