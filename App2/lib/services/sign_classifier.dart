import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/classification_result.dart';

class SignClassifier {
  Interpreter? _interpreter;
  bool _isInitialized = false;
  List<String> _labels = const ['Open', 'Close', 'Pointer', 'OK'];
  int _outputClassCount = 0;

  bool get isInitialized => _isInitialized;
  List<String> get labels => List<String>.unmodifiable(_labels);

  Future<void> initialize() async {
    try {
      const modelPath = 'assets/models/keypoint_classifier.tflite';
      _interpreter = await Interpreter.fromAsset(modelPath);
      _labels = await _loadLabels();

      final outputShape = _interpreter!.getOutputTensor(0).shape;
      _outputClassCount = outputShape.isNotEmpty
          ? outputShape.last
          : _labels.length;
      if (_outputClassCount <= 0) {
        _outputClassCount = _labels.length;
      }

      if (_labels.length > _outputClassCount) {
        _labels = _labels.sublist(0, _outputClassCount);
      } else if (_labels.length < _outputClassCount) {
        final paddedLabels = List<String>.from(_labels);
        for (var i = paddedLabels.length; i < _outputClassCount; i++) {
          paddedLabels.add('Class_$i');
        }
        _labels = paddedLabels;
      }

      _isInitialized = true;
      debugPrint(
        'SignClassifier initialized: ${_labels.length} labels: $_labels',
      );
      debugPrint('Input shape: ${_interpreter!.getInputTensor(0).shape}');
      debugPrint('Output shape: $outputShape');
    } catch (e) {
      debugPrint('Error initializing SignClassifier: $e');
      rethrow;
    }
  }

  ClassificationResult? classify(List<double> preprocessedLandmarks) {
    if (!_isInitialized || _interpreter == null) {
      return null;
    }

    if (preprocessedLandmarks.length != 42) {
      debugPrint(
        'Invalid input: expected 42 values, got ${preprocessedLandmarks.length}',
      );
      return null;
    }

    try {
      final input = Float32List.fromList(preprocessedLandmarks);
      final inputTensor = input.reshape([1, 42]);
      final output = List<List<double>>.generate(
        1,
        (_) => List<double>.filled(_outputClassCount, 0.0),
      );

      _interpreter!.run(inputTensor, output);

      final probabilities = List<double>.from(output[0]);
      if (probabilities.isEmpty) {
        debugPrint('Classifier returned an empty output tensor');
        return null;
      }

      final softmaxProbs = _softmax(probabilities);

      var maxIndex = 0;
      var maxProb = softmaxProbs[0];
      for (var i = 1; i < softmaxProbs.length; i++) {
        if (softmaxProbs[i] > maxProb) {
          maxProb = softmaxProbs[i];
          maxIndex = i;
        }
      }

      return ClassificationResult(
        label: _labels[maxIndex],
        labelIndex: maxIndex,
        confidence: softmaxProbs[maxIndex],
        probabilities: Map.fromIterables(_labels, softmaxProbs),
      );
    } catch (e) {
      debugPrint('Error during classification: $e');
      return null;
    }
  }

  List<double> _softmax(List<double> logits) {
    final sum = logits.fold(0.0, (a, b) => a + b);
    if ((sum - 1.0).abs() < 0.1 && logits.every((v) => v >= 0)) {
      return logits;
    }

    final maxLogit = logits.reduce((a, b) => a > b ? a : b);
    final expValues = logits.map((l) => exp(l - maxLogit)).toList();
    final expSum = expValues.fold(0.0, (a, b) => a + b);
    return expValues.map((e) => e / expSum).toList();
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }

  Future<List<String>> _loadLabels() async {
    try {
      const labelsPath = 'assets/models/keypoint_classifier_label.csv';
      final csv = await rootBundle.loadString(labelsPath);
      return csv
          .replaceAll('\uFEFF', '')
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
    } catch (_) {
      return _labels;
    }
  }
}
