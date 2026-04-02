import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/classification_result.dart';

/// On-device ISL sign classifier backed by the INT8-quantized TFLite model
/// trained in test/light_weight/train.py.
///
/// Input pipeline (must exactly match predict.py):
///   1. Left-hand landmarks  (21 × xyz) + Right-hand landmarks (21 × xyz)
///      → 126-dim float vector, absent hand = all zeros
///   2. Wrist-relative per hand (subtract landmark 0)
///   3. Feature-wise normalization: (x − mean) / std
///   4. Quantize to int8: round(x / input_scale + input_zero_point)
///   5. Run interpreter
///   6. Dequantize int8 output: (y − output_zero_point) × output_scale
///   7. argmax → label + softmax confidence
class TfliteClassifier {
  static const String _modelAsset = 'assets/models/sign_classifier.tflite';
  static const String _labelsAsset = 'assets/models/sign_labels.txt';
  static const String _normAsset = 'assets/models/sign_norm.json';

  static const int _landmarkDim = 126; // 21 lm × 3 (x,y,z) × 2 hands

  Interpreter? _interpreter;
  List<String> _labels = [];
  List<double> _mean = [];
  List<double> _std = [];

  // INT8 quantization params (read from model tensor metadata)
  double _inputScale = 0.0;
  int _inputZeroPoint = 0;
  double _outputScale = 0.0;
  int _outputZeroPoint = 0;
  bool _isInt8Input = false;
  bool _isInt8Output = false;

  bool _isReady = false;
  String? _loadError;

  bool get isReady => _isReady;
  String? get loadError => _loadError;
  List<String> get labels => _labels;

  Future<void> load() async {
    try {
      // ── Load TFLite model ──────────────────────────────────────────────────
      final interpreterOptions = InterpreterOptions()..threads = 2;
      _interpreter = await Interpreter.fromAsset(
        _modelAsset,
        options: interpreterOptions,
      );

      // ── Read quantization params ───────────────────────────────────────────
      final inputTensor  = _interpreter!.getInputTensor(0);
      final outputTensor = _interpreter!.getOutputTensor(0);

      _inputScale      = inputTensor.params.scale;
      _inputZeroPoint  = inputTensor.params.zeroPoint;
      _outputScale     = outputTensor.params.scale;
      _outputZeroPoint = outputTensor.params.zeroPoint;

      // INT8 model: scale != 0 and dtype is int8 (value 9 in TFLite enum)
      _isInt8Input  = _inputScale  != 0.0 && inputTensor.type  == TensorType.int8;
      _isInt8Output = _outputScale != 0.0 && outputTensor.type == TensorType.int8;

      // ── Load labels ────────────────────────────────────────────────────────
      final labelsStr = await rootBundle.loadString(_labelsAsset);
      _labels = labelsStr
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      // ── Load normalization stats ───────────────────────────────────────────
      final normStr = await rootBundle.loadString(_normAsset);
      final normJson = json.decode(normStr) as Map<String, dynamic>;
      _mean = (normJson['mean'] as List).map((v) => (v as num).toDouble()).toList();
      _std  = (normJson['std']  as List).map((v) => (v as num).toDouble()).toList();

      if (_mean.length != _landmarkDim || _std.length != _landmarkDim) {
        throw StateError(
          'normalization.json mean/std length mismatch: '
          'expected $_landmarkDim, got ${_mean.length}/${_std.length}',
        );
      }

      _isReady = true;
      debugPrint(
        '[TfliteClassifier] ready — ${_labels.length} classes, '
        'int8_input=$_isInt8Input, int8_output=$_isInt8Output',
      );
    } catch (e, st) {
      _isReady = false;
      _loadError = e.toString();
      debugPrint('[TfliteClassifier] load error: $e\n$st');
    }
  }

  /// Classify a hand pose from MediaPipe landmarks.
  ///
  /// [leftLandmarks]  — 21 landmarks [[x,y,z], ...] for the LEFT hand,
  ///                    or null / empty when no left hand is detected.
  /// [rightLandmarks] — 21 landmarks [[x,y,z], ...] for the RIGHT hand,
  ///                    or null / empty when no right hand is detected.
  ///
  /// Absent hand → all-zero block in the 126-dim vector.
  ///
  /// Returns null if the model is not ready or confidence is too low.
  ClassificationResult? classify({
    List<List<double>>? leftLandmarks,
    List<List<double>>? rightLandmarks,
    double minConfidence = 0.4,
  }) {
    if (!_isReady || _interpreter == null) return null;

    // ── Build 126-dim feature vector ─────────────────────────────────────────
    final features = List<double>.filled(_landmarkDim, 0.0);
    _fillHand(features, 0,  leftLandmarks);   // slots 0..62
    _fillHand(features, 63, rightLandmarks);  // slots 63..125

    // ── Normalize: (x − mean) / std ──────────────────────────────────────────
    for (var i = 0; i < _landmarkDim; i++) {
      features[i] = (features[i] - _mean[i]) / _std[i];
    }

    // ── Run inference ─────────────────────────────────────────────────────────
    final probs = _runInference(features);
    if (probs == null) return null;

    // ── Argmax + confidence ───────────────────────────────────────────────────
    var bestIdx = 0;
    var bestVal = probs[0];
    for (var i = 1; i < probs.length; i++) {
      if (probs[i] > bestVal) {
        bestVal = probs[i];
        bestIdx = i;
      }
    }

    if (bestVal < minConfidence) return null;
    if (bestIdx >= _labels.length) return null;

    final probMap = <String, double>{};
    for (var i = 0; i < probs.length && i < _labels.length; i++) {
      probMap[_labels[i]] = probs[i];
    }

    return ClassificationResult(
      label: _labels[bestIdx],
      labelIndex: bestIdx,
      confidence: bestVal,
      probabilities: probMap,
    );
  }

  // ── Private helpers ──────────────────────────────────────────────────────────

  /// Fills [features] starting at [offset] with wrist-relative x,y,z values
  /// for [landmarks]. If null/empty, the block stays zero (absent hand).
  void _fillHand(
    List<double> features,
    int offset,
    List<List<double>>? landmarks,
  ) {
    if (landmarks == null || landmarks.length != 21) return;

    // Wrist-relative: subtract landmark 0 (wrist) from all points
    final wx = landmarks[0][0];
    final wy = landmarks[0][1];
    final wz = landmarks[0].length > 2 ? landmarks[0][2] : 0.0;

    for (var i = 0; i < 21; i++) {
      final lm = landmarks[i];
      final base = offset + i * 3;
      features[base]     = lm[0] - wx;
      features[base + 1] = lm[1] - wy;
      features[base + 2] = (lm.length > 2 ? lm[2] : 0.0) - wz;
    }
  }

  List<double>? _runInference(List<double> features) {
    try {
      if (_isInt8Input) {
        // Quantize float → int8
        final input = List<int>.generate(_landmarkDim, (i) {
          final q = (features[i] / _inputScale + _inputZeroPoint).round();
          return q.clamp(-128, 127);
        });
        final inputTensor = [input]; // shape [1, 126]

        if (_isInt8Output) {
          final outputRaw = [List<int>.filled(_labels.length, 0)];
          _interpreter!.run(inputTensor, outputRaw);
          // Dequantize int8 → float
          return outputRaw[0]
              .map((v) => (v - _outputZeroPoint) * _outputScale)
              .toList();
        } else {
          final outputFloat = [List<double>.filled(_labels.length, 0.0)];
          _interpreter!.run(inputTensor, outputFloat);
          return outputFloat[0];
        }
      } else {
        final inputTensor = [features]; // shape [1, 126]
        final outputFloat = [List<double>.filled(_labels.length, 0.0)];
        _interpreter!.run(inputTensor, outputFloat);
        return outputFloat[0];
      }
    } catch (e) {
      debugPrint('[TfliteClassifier] inference error: $e');
      return null;
    }
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isReady = false;
  }
}
