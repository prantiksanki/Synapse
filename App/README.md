# SYNAPSE — Real-time Sign Language to Natural Language

SYNAPSE is an Android Flutter application that:

1. Captures live camera frames
2. Detects hand landmarks via MediaPipe
3. Classifies the gesture using a TFLite model (keypoint_classifier.tflite)
4. Accumulates detected signs into words via a smart letter buffer
5. Converts sign keywords into natural English sentences using a locally-running TinyLlama-1.1B LLM (llama.cpp, runs fully on-device)

---

## Architecture

```
Camera (YUV420) → MediaPipeService → GestureClassifier (TFLite)
                                             ↓
                                        WordBuffer
                                        (dedup + word boundary)
                                             ↓
                                        LlmService (llama.cpp JNI)
                                             ↓
                                        CameraScreen UI
```

---

## Prerequisites

| Tool | Version |
|------|---------|
| Flutter SDK | 3.19+ |
| Android Studio | Hedgehog / Iguana |
| Android NDK | 25.1.8937393 |
| CMake | 3.22.1+ |
| Android device | API 24+ (Android 7+), arm64-v8a |

---

## Quick Start

### 1. Clone and open

```bash
cd e:/Project/Synapse/App
flutter pub get
```

### 2. Add the TFLite model

The gesture classification model must be placed at:

```
assets/models/keypoint_classifier.tflite
```

Copy it from the existing project:

```bash
cp ../hand-gesture-recognition-mediapipe/model/keypoint_classifier/keypoint_classifier.tflite \
   assets/models/keypoint_classifier.tflite
```

### 3. Run on device

```bash
flutter run --release
```

On first launch the app will show a **Download** screen — tap **Download TinyLlama** to fetch the ~670 MB GGUF model from HuggingFace. This requires an internet connection and takes a few minutes depending on your connection speed.

Tap **Skip** to use the app without LLM sentence generation (gesture detection and word building still work).

---

## Integrating Real llama.cpp

The native C++ layer currently ships with **stub implementations** so the app builds and runs without a full llama.cpp compile. To enable real on-device inference:

1. Clone llama.cpp into the native source directory:

```bash
cd android/app/src/main/cpp
git clone https://github.com/ggerganov/llama.cpp
```

2. Update `CMakeLists.txt` to add the llama.cpp subdirectory and link it.

3. Replace the three stub functions in `llama_bridge.cpp` with real llama.cpp API calls — the file contains detailed TODO comments with exact function names and signatures.

See: https://github.com/ggerganov/llama.cpp/blob/master/examples/simple/simple.cpp

---

## Gesture Labels

Labels are loaded from `assets/labels/keypoint_classifier_label.csv` at runtime. The included file mirrors the labels from the `hand-gesture-recognition-mediapipe` model in this repository. To use a custom-trained model, replace both the `.tflite` file and the `.csv` label list.

Special gestures:
- `SPACE` — commits the current in-progress word immediately
- `DELETE` — removes the last letter (or restores the previous word)

---

## File Structure

```
App/
├── pubspec.yaml
├── assets/
│   ├── labels/
│   │   └── keypoint_classifier_label.csv
│   └── models/
│       └── keypoint_classifier.tflite      ← you must add this
├── lib/
│   ├── main.dart                           ← app entry point + AppState
│   ├── camera_service.dart                 ← camera init + frame streaming
│   ├── mediapipe_service.dart              ← hand landmark detection
│   ├── gesture_classifier.dart             ← TFLite inference
│   ├── word_buffer.dart                    ← letter → word accumulation
│   ├── llm_service.dart                    ← Dart side of llama.cpp bridge
│   ├── model_downloader.dart               ← HuggingFace GGUF download
│   └── ui/
│       ├── camera_screen.dart              ← main live-view screen
│       ├── result_widget.dart              ← generated sentence card
│       └── download_screen.dart            ← first-run model download
└── android/
    ├── build.gradle
    ├── settings.gradle
    └── app/
        ├── build.gradle                    ← NDK + CMake config
        └── src/main/
            ├── AndroidManifest.xml
            ├── kotlin/com/synapse/app/
            │   ├── MainActivity.kt
            │   ├── LlamaPlugin.kt          ← Flutter MethodChannel
            │   └── LlamaService.kt         ← JNI wrapper
            └── cpp/
                ├── CMakeLists.txt
                └── llama_bridge.cpp        ← JNI bridge (stubs → replace with llama.cpp)
```

---

## Permissions

| Permission | Purpose |
|-----------|---------|
| `CAMERA` | Live hand gesture capture |
| `INTERNET` | Downloading TinyLlama model on first run |
| `READ/WRITE_EXTERNAL_STORAGE` | Storing the ~670 MB GGUF model file |
| `MANAGE_EXTERNAL_STORAGE` | Android 11+ broad storage access for model file |

---

## Known Limitations

- The llama.cpp native layer is a **stub** until real llama.cpp is integrated — the "Generate Sentence" button will echo the detected sign keywords back without LLM transformation.
- The MediaPipe landmark platform channel is not yet implemented on the Kotlin side — the app falls back to mock landmarks for classifier testing.
- Only `arm64-v8a` and `x86_64` ABIs are built by default. Add `armeabi-v7a` in `app/build.gradle` if needed for older 32-bit devices.
