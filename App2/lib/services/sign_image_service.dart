import 'dart:convert';

import 'package:flutter/services.dart';

/// A single entry in a sign-image / sign-gif sequence.
/// Can be:
/// - a character with its PNG image bytes via [SignImageSegment.character]
/// - a whole-word GIF asset path via [SignImageSegment.gif]
/// - a word-space gap marker via [SignImageSegment.wordSpace]
class SignImageSegment {
  final String? char;
  final Uint8List? imageBytes;
  final bool isWordSpace;
  final String? gifAssetPath;
  final String? word;

  const SignImageSegment.character({
    required String this.char,
    required Uint8List this.imageBytes,
  })  : isWordSpace = false,
        gifAssetPath = null,
        word = null;

  const SignImageSegment.wordSpace()
      : char = null,
        imageBytes = null,
        isWordSpace = true,
        gifAssetPath = null,
        word = null;

  const SignImageSegment.gif({
    required String this.word,
    required String this.gifAssetPath,
  })  : char = null,
        imageBytes = null,
        isWordSpace = false;

  bool get hasImage => imageBytes != null;
  bool get isGif => gifAssetPath != null;
}

/// Loads sign-language images from bundled assets and converts text into
/// [SignImageSegment] sequences for display.
class SignImageService {
  final Map<String, Uint8List> _imageCache = {};
  Map<String, String> _manifest = {};
  Map<String, String> _wordGifMap = {};

  bool _loaded = false;
  String? _loadError;

  bool get isLoaded => _loaded;
  String? get loadError => _loadError;

  Future<void> initialize() async {
    try {
      final manifestJson =
          await rootBundle.loadString('assets/sign_images/manifest.json');
      final raw = jsonDecode(manifestJson) as Map<String, dynamic>;
      _manifest = raw.map((k, v) => MapEntry(k.toUpperCase(), v as String));

      for (final entry in _manifest.entries) {
        final data = await rootBundle.load('assets/sign_images/${entry.value}');
        _imageCache[entry.key] = data.buffer.asUint8List();
      }

      final availableGifAssets = await _loadAvailableGifAssets();
      _wordGifMap = {
        for (final asset in availableGifAssets) _wordFromAssetPath(asset): asset,
      };

      try {
        final wordJson =
            await rootBundle.loadString('assets/sign_videos/word_manifest.json');
        final wordRaw = jsonDecode(wordJson) as Map<String, dynamic>;
        for (final entry in wordRaw.entries) {
          final resolvedPath = _resolveGifAssetPath(
            entry.value as String,
            availableGifAssets,
          );
          if (resolvedPath != null) {
            _wordGifMap[entry.key.toLowerCase()] = resolvedPath;
          }
        }
      } catch (_) {
        // Direct GIF discovery above already provides working word mapping.
      }

      _loaded = true;
    } catch (e) {
      _loadError = e.toString();
      _loaded = false;
    }
  }

  List<SignImageSegment> textToSegments(String text) {
    final segments = <SignImageSegment>[];
    final words = text.toUpperCase().trim().split(RegExp(r'\s+'));

    for (var wi = 0; wi < words.length; wi++) {
      if (words[wi].isEmpty) continue;
      if (wi > 0) segments.add(const SignImageSegment.wordSpace());

      final wordLower = words[wi].toLowerCase();
      final gifPath = _wordGifMap[wordLower];

      if (gifPath != null) {
        segments.add(
          SignImageSegment.gif(
            word: words[wi],
            gifAssetPath: gifPath,
          ),
        );
        continue;
      }

      for (final char in words[wi].split('')) {
        final image = _imageCache[char];
        if (image != null) {
          segments.add(
            SignImageSegment.character(char: char, imageBytes: image),
          );
        }
      }
    }
    return segments;
  }

  String extractKeywordsFallback(String sentence) {
    const stopWords = {
      'a', 'an', 'the', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
      'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could',
      'should', 'may', 'might', 'shall', 'can', 'to', 'of', 'in', 'on',
      'at', 'by', 'for', 'with', 'from', 'about', 'into', 'through', 'up',
      'i', 'you', 'he', 'she', 'it', 'we', 'they', 'me', 'him', 'her',
      'us', 'them', 'my', 'your', 'his', 'its', 'our', 'their', 'this',
      'that', 'and', 'but', 'or', 'so', 'if', 'not', 'no', 'yes', 'please',
    };

    final words = sentence
        .toLowerCase()
        .replaceAll(RegExp(r"[^\w\s']"), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && !stopWords.contains(w))
        .toList();

    return words.join(' ');
  }

  Uint8List? imageForChar(String char) => _imageCache[char.toUpperCase()];

  void dispose() => _imageCache.clear();

  Future<Set<String>> _loadAvailableGifAssets() async {
    final manifestJson = await rootBundle.loadString('AssetManifest.json');
    final raw = jsonDecode(manifestJson) as Map<String, dynamic>;
    return raw.keys
        .where(
          (path) =>
              path.startsWith('assets/sign_videos/') &&
              path.toLowerCase().endsWith('.gif'),
        )
        .toSet();
  }

  String _wordFromAssetPath(String assetPath) {
    final fileName = assetPath.split('/').last;
    final withoutExt = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    return withoutExt.toLowerCase();
  }

  String? _resolveGifAssetPath(
    String requestedPath,
    Set<String> availableGifAssets,
  ) {
    if (availableGifAssets.contains(requestedPath)) return requestedPath;

    final requestedName = requestedPath
        .split('/')
        .last
        .replaceAll(RegExp(r'\.[^.]+$'), '')
        .toLowerCase();

    for (final asset in availableGifAssets) {
      if (_wordFromAssetPath(asset) == requestedName) {
        return asset;
      }
    }
    return null;
  }
}
