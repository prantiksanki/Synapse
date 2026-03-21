import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../models/llm_generation_result.dart';

/// On-device grammar correction using T5-small converted to TFLite.
///
/// Two TFLite model files are required in assets/models/:
///   - t5_encoder.tflite
///   - t5_decoder.tflite
///
/// The vocabulary file must also be present:
///   - t5_vocab.txt  (one sentencepiece token per line, index = id)
///
/// Run tools/export_t5_tflite.py once on a desktop machine to produce
/// these three files, then place them in App2/assets/models/.
class T5GrammarService {
  static const String _encoderAsset = 'assets/models/t5_encoder.tflite';
  static const String _decoderAsset = 'assets/models/t5_decoder.tflite';
  static const String _vocabAsset = 'assets/models/t5_vocab.txt';

  // T5 special token ids (standard for t5-small / vennify/t5-base-grammar)
  static const int _padId = 0;
  static const int _eosId = 1;
  static const int _decoderStartId = 0; // T5 decoder starts with pad token

  static const int _maxInputLen = 64;
  static const int _maxOutputLen = 64;

  Interpreter? _encoder;
  Interpreter? _decoder;
  List<String> _vocab = [];
  Map<String, int> _tokenToId = {};

  bool _ready = false;
  String? _loadError;

  bool get isReady => _ready;
  String? get loadError => _loadError;

  /// Load both TFLite models and the vocabulary from assets.
  Future<void> load() async {
    try {
      // Load vocabulary
      final vocabData = await rootBundle.loadString(_vocabAsset);
      _vocab = vocabData.split('\n').map((l) => l.trimRight()).toList();
      _tokenToId = {for (var i = 0; i < _vocab.length; i++) _vocab[i]: i};

      // Load TFLite models
      final encoderOptions = InterpreterOptions()..threads = 2;
      final decoderOptions = InterpreterOptions()..threads = 2;

      _encoder = await Interpreter.fromAsset(
        _encoderAsset,
        options: encoderOptions,
      );
      _decoder = await Interpreter.fromAsset(
        _decoderAsset,
        options: decoderOptions,
      );

      _ready = true;
      _loadError = null;
    } catch (e) {
      _ready = false;
      _loadError = e.toString();
    }
  }

  /// Correct grammar in [roughSentence].
  /// Returns an [LlmGenerationResult] with the corrected sentence.
  Future<LlmGenerationResult> correctGrammar(String roughSentence) async {
    final sw = Stopwatch()..start();

    if (!_ready) {
      // Dart-side fallback when model isn't loaded
      final sentence = _dartFallback(roughSentence);
      sw.stop();
      return LlmGenerationResult(
        inputTokens: roughSentence,
        sentence: sentence,
        latencyMs: sw.elapsedMilliseconds,
        source: 'Dart fallback',
      );
    }

    try {
      // Prefix input with "grammar: " as expected by vennify/t5-base-grammar
      final prefixed = 'grammar: ${roughSentence.trim()}';
      final inputIds = _tokenize(prefixed);

      // Run encoder
      final encoderOutput = _runEncoder(inputIds);

      // Run autoregressive decoder
      final outputIds = _runDecoder(encoderOutput, inputIds.length);

      final corrected = _detokenize(outputIds);
      sw.stop();

      return LlmGenerationResult(
        inputTokens: roughSentence,
        sentence: corrected.isNotEmpty ? corrected : roughSentence,
        latencyMs: sw.elapsedMilliseconds,
        source: 'T5-Grammar',
      );
    } catch (e) {
      sw.stop();
      return LlmGenerationResult(
        inputTokens: roughSentence,
        sentence: _dartFallback(roughSentence),
        latencyMs: sw.elapsedMilliseconds,
        source: 'Dart fallback',
        error: e.toString(),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Tokenization — lightweight SentencePiece-compatible whitespace tokenizer.
  // For production, replace with a proper SP tokenizer that matches your vocab.
  // ---------------------------------------------------------------------------

  List<int> _tokenize(String text) {
    final ids = <int>[];
    // Naive word-level tokenization; works if vocab contains whole words.
    // The export script should bake a word-level or subword vocab matched here.
    final words = text.toLowerCase().trim().split(RegExp(r'\s+'));
    for (final word in words) {
      final id = _tokenToId[word] ?? _tokenToId['<unk>'] ?? 2;
      ids.add(id);
    }
    // Pad / truncate to _maxInputLen
    while (ids.length < _maxInputLen) {
      ids.add(_padId);
    }
    return ids.sublist(0, _maxInputLen);
  }

  String _detokenize(List<int> ids) {
    final tokens = <String>[];
    for (final id in ids) {
      if (id == _eosId || id == _padId) break;
      if (id >= 0 && id < _vocab.length) {
        final token = _vocab[id];
        if (token.isNotEmpty && token != '<pad>' && token != '</s>') {
          tokens.add(token);
        }
      }
    }
    return tokens.join(' ').trim();
  }

  // ---------------------------------------------------------------------------
  // Encoder
  // ---------------------------------------------------------------------------

  /// Returns encoder hidden states: Float32List of shape [1, seqLen, hiddenDim]
  Float32List _runEncoder(List<int> inputIds) {
    final encoder = _encoder!;
    final seqLen = _maxInputLen;

    // input_ids: [1, seqLen]
    final inputIdsTensor = [inputIds];
    // attention_mask: [1, seqLen] — 1 for real tokens, 0 for padding
    final attentionMask = [inputIds.map((id) => id != _padId ? 1 : 0).toList()];

    // Encoder output shape: [1, seqLen, hiddenDim] — hiddenDim=512 for t5-small
    const hiddenDim = 512;
    final outputBuffer = List.generate(
      1,
      (_) => List.generate(seqLen, (_) => List.filled(hiddenDim, 0.0)),
    );

    encoder.runForMultipleInputs(
      [inputIdsTensor, attentionMask],
      {0: outputBuffer},
    );

    // Flatten to Float32List for decoder input
    final flat = Float32List(seqLen * hiddenDim);
    var idx = 0;
    for (final row in outputBuffer[0]) {
      for (final val in row) {
        flat[idx++] = val;
      }
    }
    return flat;
  }

  // ---------------------------------------------------------------------------
  // Decoder — greedy autoregressive decoding
  // ---------------------------------------------------------------------------

  List<int> _runDecoder(Float32List encoderHiddenStates, int encoderSeqLen) {
    final decoder = _decoder!;
    const hiddenDim = 512;
    final outputIds = <int>[];
    int prevTokenId = _decoderStartId;

    for (var step = 0; step < _maxOutputLen; step++) {
      // decoder_input_ids: [1, 1]
      final decoderInput = [[prevTokenId]];

      // encoder_hidden_states reshaped to [1, seqLen, hiddenDim]
      final encoderStates = List.generate(
        1,
        (_) => List.generate(
          encoderSeqLen,
          (i) => List.generate(
            hiddenDim,
            (j) => encoderHiddenStates[i * hiddenDim + j],
          ),
        ),
      );

      // logits output: [1, 1, vocabSize]
      final vocabSize = _vocab.length;
      final logits = List.generate(
        1,
        (_) => List.generate(1, (_) => List.filled(vocabSize, 0.0)),
      );

      decoder.runForMultipleInputs(
        [decoderInput, encoderStates],
        {0: logits},
      );

      // Greedy: pick argmax over vocab
      final stepLogits = logits[0][0];
      var bestId = 0;
      var bestVal = stepLogits[0];
      for (var v = 1; v < stepLogits.length; v++) {
        if (stepLogits[v] > bestVal) {
          bestVal = stepLogits[v];
          bestId = v;
        }
      }

      if (bestId == _eosId) break;
      outputIds.add(bestId);
      prevTokenId = bestId;
    }

    return outputIds;
  }

  // ---------------------------------------------------------------------------
  // Dart fallback — used before model loads or on error
  // ---------------------------------------------------------------------------

  String _dartFallback(String input) {
    final tokens = input
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return '';
    if (tokens.length == 1) return 'I want to say: ${tokens.first.toLowerCase()}.';
    // Capitalise and append period
    final joined = tokens.map((t) => t.toLowerCase()).join(' ');
    final capitalised = joined[0].toUpperCase() + joined.substring(1);
    return capitalised.endsWith('.') ? capitalised : '$capitalised.';
  }

  void dispose() {
    _encoder?.close();
    _decoder?.close();
    _encoder = null;
    _decoder = null;
    _ready = false;
  }
}
