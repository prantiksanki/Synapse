// gesture_classifier.dart — TFLite-based hand gesture classifier.
//
// Loads keypoint_classifier.tflite (trained on 21×2 MediaPipe landmarks)
// and maps softmax output probabilities to the gesture labels defined in
// keypoint_classifier_label.csv.
//
// Pipeline:
//   List<double> (42 values, normalised) → TFLite interpreter → softmax → top-1 label + confidence

import 'dart:developer' as dev;

import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Classifies a single set of 21 hand landmarks into a gesture label.
class GestureClassifier {
  // -------------------------------------------------------------------------
  // Asset paths
  // -------------------------------------------------------------------------

  static const String _modelAsset = 'assets/models/keypoint_classifier.tflite';
  static const String _labelAsset = 'assets/labels/keypoint_classifier_label.csv';

  // -------------------------------------------------------------------------
  // Internal state
  // -------------------------------------------------------------------------

  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  /// Number of gesture classes the model was trained on.
  int get numClasses => _labels.length;

  // -------------------------------------------------------------------------
  // Initialization
  // -------------------------------------------------------------------------

  /// Load the TFLite model and label list from the Flutter asset bundle.
  ///
  /// Must be called before [classify].
  Future<void> load() async {
    try {
      await _loadLabels();
      await _loadModel();
      _isLoaded = true;
      dev.log(
        'GestureClassifier loaded: ${_labels.length} classes.',
        name: 'GestureClassifier',
      );
    } catch (e) {
      _isLoaded = false;
      dev.log('GestureClassifier load failed: $e', name: 'GestureClassifier', level: 900);
      rethrow;
    }
  }

  Future<void> _loadLabels() async {
    final raw = await rootBundle.loadString(_labelAsset);
    _labels = raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    dev.log('Labels loaded: $_labels', name: 'GestureClassifier');
  }

  Future<void> _loadModel() async {
    final options = InterpreterOptions()
      ..threads = 2; // Use 2 threads for inference

    _interpreter = await Interpreter.fromAsset(
      _modelAsset,
      options: options,
    );

    // Log input/output tensor shapes for debugging
    final inputShape  = _interpreter!.getInputTensor(0).shape;
    final outputShape = _interpreter!.getOutputTensor(0).shape;
    dev.log(
      'TFLite model loaded — input: $inputShape, output: $outputShape',
      name: 'GestureClassifier',
    );
  }

  // -------------------------------------------------------------------------
  // Inference
  // -------------------------------------------------------------------------

  /// Classify a normalised landmark vector.
  ///
  /// [landmarks] must contain exactly 42 doubles (21 landmarks × [x, y]).
  ///
  /// Returns a map with:
  ///   • 'label'      → String — the predicted gesture name
  ///   • 'confidence' → double — probability of the top prediction [0.0 – 1.0]
  ///   • 'index'      → int    — class index of the top prediction
  Map<String, dynamic> classify(List<double> landmarks) {
    if (!_isLoaded || _interpreter == null) {
      return {'label': 'unknown', 'confidence': 0.0, 'index': -1};
    }

    if (landmarks.length != 42) {
      dev.log(
        'classify() expected 42 values, got ${landmarks.length}',
        name: 'GestureClassifier',
        level: 900,
      );
      return {'label': 'unknown', 'confidence': 0.0, 'index': -1};
    }

    try {
      // ---- Prepare input tensor ----
      // Shape: [1, 42] — batch of one sample with 42 feature values
      final input = [landmarks.map((v) => v.toDouble()).toList()];

      // ---- Prepare output tensor ----
      // Shape: [1, numClasses] — softmax probabilities
      final numClasses = _labels.length;
      final output = [List<double>.filled(numClasses, 0.0)];

      // ---- Run inference ----
      _interpreter!.run(input, output);

      final probabilities = output[0];

      // ---- Find top-1 prediction ----
      int topIndex = 0;
      double topProb = probabilities[0];
      for (int i = 1; i < probabilities.length; i++) {
        if (probabilities[i] > topProb) {
          topProb  = probabilities[i];
          topIndex = i;
        }
      }

      final label = topIndex < _labels.length ? _labels[topIndex] : 'unknown';

      return {
        'label':      label,
        'confidence': topProb,
        'index':      topIndex,
      };
    } catch (e) {
      dev.log('Inference error: $e', name: 'GestureClassifier', level: 900);
      return {'label': 'unknown', 'confidence': 0.0, 'index': -1};
    }
  }

  // -------------------------------------------------------------------------
  // Cleanup
  // -------------------------------------------------------------------------

  /// Release TFLite interpreter resources.
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isLoaded = false;
    dev.log('GestureClassifier disposed.', name: 'GestureClassifier');
  }
}
