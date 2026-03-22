import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:onnxruntime/onnxruntime.dart';
import '../models/llm_generation_result.dart';

/// On-device grammar correction using T5 exported to ONNX.
/// Model files are downloaded on first launch by [T5ModelDownloader].
class T5GrammarService {
  static const int _padId          = 0;
  static const int _eosId          = 1;
  static const int _decoderStartId = 0;
  static const int _maxInputLen    = 64;
  static const int _maxOutputLen   = 64;

  OrtSession? _encoder;
  OrtSession? _decoder;
  List<String> _encoderInputNames = const [];
  List<String> _decoderInputNames = const [];
  List<String> _vocab      = [];
  Map<String, int> _tokenToId = {};
  int _hiddenDim           = 768; // read from t5_config.txt at load time

  bool _ready       = false;
  String? _loadError;

  bool get isReady      => _ready;
  String? get loadError => _loadError;

  /// Load encoder + decoder ONNX sessions and vocabulary from local file paths.
  /// [hiddenDim] comes from t5_config.txt (768 for this model).
  Future<void> load({
    required String encoderPath,
    required String decoderPath,
    required String vocabPath,
    int hiddenDim = 768,
  }) async {
    try {
      dispose();
      for (final entry in {
        'encoder': encoderPath,
        'decoder': decoderPath,
        'vocab':   vocabPath,
      }.entries) {
        final f = File(entry.value);
        if (!await f.exists() || await f.length() < 1024) {
          throw Exception('Model file missing or corrupt: ${entry.key}');
        }
      }

      OrtEnv.instance.init();

      final opts = OrtSessionOptions()
        ..setInterOpNumThreads(2)
        ..setIntraOpNumThreads(2);

      _encoder   = OrtSession.fromFile(File(encoderPath), opts);
      _decoder   = OrtSession.fromFile(File(decoderPath), opts);
      _encoderInputNames = _encoder!.inputNames;
      _decoderInputNames = _decoder!.inputNames;
      _hiddenDim = hiddenDim;

      // Parse tokenizer.json — HuggingFace format:
      // { "model": { "vocab": { "<token>": id, ... } } }
      await _loadVocabulary(vocabPath);

      _ready     = true;
      _loadError = null;
    } catch (e) {
      _ready     = false;
      _loadError = e.toString();
    }
  }

  Future<void> _loadVocabulary(String vocabPath) async {
    try {
      final raw = await File(vocabPath).readAsString();
      final decoded = jsonDecode(raw);
      final vocabEntries = _extractVocabEntries(decoded);
      if (vocabEntries.isEmpty) {
        throw const FormatException('Tokenizer vocabulary is empty.');
      }
      _setVocabulary(vocabEntries);
    } on FormatException {
      await _loadBundledPlaintextVocab();
    } on TypeError {
      await _loadBundledPlaintextVocab();
    }
  }

  Map<String, int> _extractVocabEntries(dynamic decoded) {
    if (decoded is! Map) {
      throw const FormatException('Tokenizer file is not a JSON object.');
    }

    final root = Map<String, dynamic>.from(decoded);
    final model = root['model'];
    final tokenizer = root['tokenizer'];
    final candidates = <dynamic>[
      root['vocab'],
      model is Map ? model['vocab'] : null,
      tokenizer is Map ? tokenizer['vocab'] : null,
    ];

    for (final candidate in candidates) {
      final parsed = _parseVocabCandidate(candidate);
      if (parsed.isNotEmpty) {
        parsed.addAll(_parseAddedTokens(root['added_tokens']));
        return parsed;
      }
    }

    throw const FormatException('Unsupported tokenizer vocabulary format.');
  }

  Map<String, int> _parseVocabCandidate(dynamic candidate) {
    if (candidate is Map) {
      final result = <String, int>{};
      for (final entry in candidate.entries) {
        final id = _asInt(entry.value);
        if (id != null) {
          result[entry.key.toString()] = id;
        }
      }
      return result;
    }

    if (candidate is List) {
      final result = <String, int>{};
      for (var index = 0; index < candidate.length; index++) {
        final entry = candidate[index];
        if (entry is String) {
          result[entry] = index;
          continue;
        }
        if (entry is List && entry.length >= 2) {
          final token = entry[0]?.toString();
          final id = _asInt(entry[1]);
          if (token != null && id != null) {
            result[token] = id;
          }
          continue;
        }
        if (entry is Map) {
          final token = entry['token']?.toString() ?? entry['content']?.toString();
          final id = _asInt(entry['id'] ?? entry['index']);
          if (token != null && id != null) {
            result[token] = id;
          }
        }
      }
      return result;
    }

    return const {};
  }

  Map<String, int> _parseAddedTokens(dynamic addedTokens) {
    if (addedTokens is! List) {
      return const {};
    }

    final result = <String, int>{};
    for (final entry in addedTokens) {
      if (entry is! Map) {
        continue;
      }
      final token = entry['content']?.toString() ?? entry['token']?.toString();
      final id = _asInt(entry['id'] ?? entry['index']);
      if (token != null && id != null) {
        result[token] = id;
      }
    }
    return result;
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  Future<void> _loadBundledPlaintextVocab() async {
    final raw = await rootBundle.loadString('assets/models/t5_vocab.txt');
    final lines = const LineSplitter()
        .convert(raw)
        .map((line) => line.trimRight())
        .toList();
    if (lines.isEmpty) {
      throw const FormatException('Bundled T5 vocabulary is empty.');
    }

    final vocabEntries = <String, int>{};
    for (var index = 0; index < lines.length; index++) {
      final token = lines[index];
      if (token.isNotEmpty) {
        vocabEntries[token] = index;
      }
    }
    _setVocabulary(vocabEntries);
  }

  void _setVocabulary(Map<String, int> vocabEntries) {
    final maxId = vocabEntries.values.reduce((a, b) => a > b ? a : b);
    _vocab = List<String>.filled(maxId + 1, '');
    _tokenToId = {};
    for (final entry in vocabEntries.entries) {
      final id = entry.value;
      if (id < 0) {
        continue;
      }
      _vocab[id] = entry.key;
      _tokenToId[entry.key] = id;
    }
  }

  /// Correct grammar in [roughSentence].
  Future<LlmGenerationResult> correctGrammar(String roughSentence) async {
    final sw = Stopwatch()..start();

    if (!_ready) {
      sw.stop();
      return LlmGenerationResult(
        inputTokens: roughSentence,
        sentence: _dartFallback(roughSentence),
        latencyMs: sw.elapsedMilliseconds,
        source: 'Dart fallback',
      );
    }

    try {
      final inputIds  = _tokenize('grammar: ${roughSentence.trim()}');
      final encOut    = _runEncoder(inputIds);
      final outputIds = _runDecoder(encOut);
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

  // ── Tokenization ──────────────────────────────────────────────────────────

  // SentencePiece word-start marker (▁ U+2581)
  static const String _sp = '\u2581';

  List<int> _tokenize(String text) {
    final ids   = <int>[];
    final words = text.toLowerCase().trim().split(RegExp(r'\s+'));

    for (var wi = 0; wi < words.length; wi++) {
      final word = words[wi];
      // Try to greedily encode each word as subword pieces.
      // First try the whole word with ▁ prefix (SentencePiece convention).
      final prefixed = wi == 0 ? word : '$_sp$word';
      if (_tokenToId.containsKey(prefixed)) {
        ids.add(_tokenToId[prefixed]!);
        continue;
      }
      // Fall back: try without prefix, then character-by-character with ▁
      if (_tokenToId.containsKey(word)) {
        ids.add(_tokenToId[word]!);
        continue;
      }
      // Greedy subword split with ▁ on first char of word
      final pieces = _greedyEncode(word, isFirst: wi == 0);
      ids.addAll(pieces);
    }

    // Append EOS
    if (ids.length < _maxInputLen) { ids.add(_eosId); }
    while (ids.length < _maxInputLen) { ids.add(_padId); }
    return ids.sublist(0, _maxInputLen);
  }

  /// Greedy longest-match subword encoding (simplified SentencePiece).
  List<int> _greedyEncode(String word, {required bool isFirst}) {
    final ids    = <int>[];
    var   pos    = 0;
    var   first  = true;

    while (pos < word.length) {
      var matched = false;
      // Try longest subword first
      for (var end = word.length; end > pos; end--) {
        final sub     = word.substring(pos, end);
        final prefix  = (first && isFirst) ? sub : (first ? '$_sp$sub' : sub);
        final noPrefix = sub;

        final id = _tokenToId[prefix] ?? _tokenToId[noPrefix];
        if (id != null) {
          ids.add(id);
          pos     = end;
          first   = false;
          matched = true;
          break;
        }
      }
      if (!matched) {
        // Unknown character — use <unk>
        ids.add(_tokenToId['<unk>'] ?? 2);
        pos++;
        first = false;
      }
    }
    return ids;
  }

  String _detokenize(List<int> ids) {
    final buffer = StringBuffer();
    for (final id in ids) {
      if (id == _eosId || id == _padId) break;
      if (id < 0 || id >= _vocab.length) continue;
      final tok = _vocab[id];
      if (tok.isEmpty || tok == '<pad>' || tok == '</s>') continue;

      if (tok.startsWith(_sp)) {
        // ▁ marks a new word boundary — add space then the word
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(tok.substring(1));
      } else {
        // Continuation piece — append directly (no space)
        buffer.write(tok);
      }
    }
    return buffer.toString().trim();
  }

  // ── Encoder ───────────────────────────────────────────────────────────────

  _EncoderResult _runEncoder(List<int> inputIds) {
    final seqLen   = _maxInputLen;

    final idData   = Int64List.fromList(inputIds);
    final maskData = Int64List.fromList(inputIds.map((id) => id != _padId ? 1 : 0).toList());

    final inputs = <String, OrtValue>{
      _resolveName(_encoderInputNames, const ['input_ids', 'encoder_input_ids']):
          OrtValueTensor.createTensorWithDataList(idData, [1, seqLen]),
    };
    final attentionMaskName = _resolveOptionalName(
      _encoderInputNames,
      const ['attention_mask', 'encoder_attention_mask'],
    );
    if (attentionMaskName != null) {
      inputs[attentionMaskName] =
          OrtValueTensor.createTensorWithDataList(maskData, [1, seqLen]);
    }

    final outputs = _encoder!.run(OrtRunOptions(), inputs);
    for (final v in inputs.values) { v.release(); }

    final raw  = (outputs.first?.value as List)[0] as List;
    final actualSeqLen = raw.length;
    final hidden = actualSeqLen > 0 ? (raw.first as List).length : _hiddenDim;
    final flat = Float32List(actualSeqLen * hidden);
    var idx    = 0;
    for (final row in raw) {
      for (final val in (row as List)) { flat[idx++] = (val as double); }
    }
    for (final o in outputs) { o?.release(); }

    // Build attention mask for use in decoder (1 for real tokens, 0 for pad)
    final maskFlat = Int64List.fromList(maskData);

    return _EncoderResult(
      hiddenStates: flat,
      attentionMask: maskFlat,
      sequenceLength: actualSeqLen,
      hiddenSize: hidden,
    );
  }

  // ── Decoder — greedy autoregressive ──────────────────────────────────────

  List<int> _runDecoder(_EncoderResult encoderResult) {
    final seqLen = encoderResult.sequenceLength;
    final hidden = encoderResult.hiddenSize;
    final outputIds = <int>[];
    int prevToken = _decoderStartId;

    final decoderInputName = _resolveName(
      _decoderInputNames,
      const ['decoder_input_ids', 'input_ids'],
    );
    final hiddenStatesName = _resolveOptionalName(
      _decoderInputNames,
      const ['encoder_hidden_states', 'encoder_outputs', 'hidden_states'],
    );
    if (hiddenStatesName == null) {
      throw StateError(
        'Unsupported decoder inputs: ${_decoderInputNames.join(', ')}',
      );
    }

    for (var step = 0; step < _maxOutputLen; step++) {
      final encData = Float32List(seqLen * hidden);
      for (var i = 0; i < seqLen * hidden; i++) {
        encData[i] = encoderResult.hiddenStates[i];
      }

      final inputs = <String, OrtValue>{
        decoderInputName: OrtValueTensor.createTensorWithDataList(
          Int64List.fromList([prevToken]),
          [1, 1],
        ),
        hiddenStatesName: OrtValueTensor.createTensorWithDataList(
          encData,
          [1, seqLen, hidden],
        ),
      };

      // Pass encoder_attention_mask if the decoder model requires it
      final encMaskName = _resolveOptionalName(
        _decoderInputNames,
        const ['encoder_attention_mask', 'attention_mask'],
      );
      if (encMaskName != null) {
        inputs[encMaskName] = OrtValueTensor.createTensorWithDataList(
          encoderResult.attentionMask,
          [1, seqLen],
        );
      }

      final outputs = _decoder!.run(OrtRunOptions(), inputs);
      for (final v in inputs.values) { v.release(); }

      final logits = ((outputs.first?.value as List)[0] as List)[0] as List;
      var bestId   = 0;
      var bestVal  = (logits[0] as double);
      for (var v = 1; v < logits.length; v++) {
        final val = (logits[v] as double);
        if (val > bestVal) { bestVal = val; bestId = v; }
      }
      for (final o in outputs) { o?.release(); }

      if (bestId == _eosId) break;
      outputIds.add(bestId);
      prevToken = bestId;
    }
    return outputIds;
  }

  String _resolveName(List<String> available, List<String> preferred) {
    final name = _resolveOptionalName(available, preferred);
    if (name == null) {
      if (available.length == 1) {
        return available.first;
      }
      throw StateError('Expected one of ${preferred.join(', ')} in ${available.join(', ')}');
    }
    return name;
  }

  String? _resolveOptionalName(List<String> available, List<String> preferred) {
    for (final candidate in preferred) {
      if (available.contains(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  // ── Dart fallback ─────────────────────────────────────────────────────────

  String _dartFallback(String input) {
    final tokens = input.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return '';
    if (tokens.length == 1) return 'I want to say: ${tokens.first.toLowerCase()}.';
    final joined = tokens.map((t) => t.toLowerCase()).join(' ');
    final cap    = joined[0].toUpperCase() + joined.substring(1);
    return cap.endsWith('.') ? cap : '$cap.';
  }

  void dispose() {
    _encoder?.release();
    _decoder?.release();
    _encoder = null;
    _decoder = null;
    _encoderInputNames = const [];
    _decoderInputNames = const [];
    _ready   = false;
  }
}

class _EncoderResult {
  const _EncoderResult({
    required this.hiddenStates,
    required this.attentionMask,
    required this.sequenceLength,
    required this.hiddenSize,
  });

  final Float32List hiddenStates;
  final Int64List attentionMask;
  final int sequenceLength;
  final int hiddenSize;
}
