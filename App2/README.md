# Sign Language Detection App

A real-time sign language detection Flutter app using MediaPipe for hand detection and TFLite for gesture classification.

## Features

- Real-time hand landmark detection using MediaPipe
- Gesture classification for 4 signs: Open, Close, Pointer, OK
- Visual hand skeleton overlay
- FPS counter and confidence display
- Pause/resume detection

## Requirements

- Android device with API level 24+ (Android 7.0+)
- Flutter SDK 3.0+
- Camera hardware

## Project Structure

```
App/
├── lib/
│   ├── main.dart                     # Entry point, provider setup
│   ├── services/
│   │   ├── camera_service.dart       # Camera stream handling
│   │   ├── hand_landmark_service.dart # MediaPipe hand detection
│   │   ├── landmark_processor.dart   # Preprocessing for classifier
│   │   └── sign_classifier.dart      # TFLite keypoint classifier
│   ├── models/
│   │   ├── hand_landmark.dart        # Landmark data model
│   │   └── classification_result.dart
│   ├── providers/
│   │   └── detection_provider.dart   # State management
│   ├── widgets/
│   │   ├── camera_preview.dart       # Camera preview widget
│   │   ├── hand_overlay_painter.dart # Draw landmarks on screen
│   │   └── gesture_display.dart      # Show detected gesture
│   └── screens/
│       └── detection_screen.dart     # Main screen
├── assets/
│   └── models/
│       └── keypoint_classifier.tflite
├── android/
│   └── app/build.gradle.kts          # minSdk 24, TFLite settings
└── pubspec.yaml
```

## Setup

1. **Install dependencies**:
   ```bash
   cd App
   flutter pub get
   ```

2. **Build debug APK**:
   ```bash
   flutter build apk --debug
   ```

3. **Run on device**:
   ```bash
   flutter run
   ```

## Supported Gestures

| Gesture | Description |
|---------|-------------|
| Open    | Open palm facing camera |
| Close   | Closed fist |
| Pointer | Index finger pointing |
| OK      | OK hand sign |

## Technical Details

### Model Specifications
- **Input**: 42 float32 values (21 landmarks x 2 coordinates)
- **Output**: 4 class probabilities
- **Model size**: ~6.3 KB

### Inference Pipeline
1. Camera captures YUV420 frames
2. hand_landmarker plugin detects hand and returns 21 landmarks
3. Landmarks are normalized relative to wrist position
4. TFLite model classifies gesture
5. Result displayed with confidence score

### Dependencies
- `camera` - Camera access
- `hand_landmarker` - MediaPipe hand detection (Android only)
- `tflite_flutter` - TensorFlow Lite inference
- `provider` - State management
- `permission_handler` - Camera permissions

## Platform Support

**Android only** - The `hand_landmarker` package currently only supports Android.

## Troubleshooting

### Camera permission denied
Ensure camera permission is granted in device settings.

### Build fails with minSdk error
The app requires minimum SDK 24. Check `android/app/build.gradle.kts`.

### Hand not detected
- Ensure good lighting
- Hold hand steady in front of camera
- Try different angles
