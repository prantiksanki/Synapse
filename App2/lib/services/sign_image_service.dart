import 'dart:convert';
import 'package:flutter/services.dart';

/// A single entry in a sign-image sequence.
/// Either a character with its image, or a word-space marker.
class SignImageSegment {
  final String? char;
  final Uint8List? imageBytes;
  final bool isWordSpace;

  const SignImageSegment.character({
    required String this.char,
    required Uint8List this.imageBytes,
  }) : isWordSpace = false;

  const SignImageSegment.wordSpace()
      : char = null,
        imageBytes = null,
        isWordSpace = true;

  bool get hasImage => imageBytes != null;
}

/// Loads sign-language images from bundled assets and converts text into
/// sequences of [SignImageSegment]s for display.
class SignImageService {
  final Map<String, Uint8List> _imageCache = {};
  Map<String, String> _manifest = {};

  bool _loaded = false;
  String? _loadError;

  bool get isLoaded => _loaded;
  String? get loadError => _loadError;

  /// Call once during app start-up (in [DetectionProvider.initialize]).
  /// Loads the manifest and caches all sign images into memory.
  Future<void> initialize() async {
    try {
      final manifestJson =
          await rootBundle.loadString('assets/sign_images/manifest.json');
      final raw = jsonDecode(manifestJson) as Map<String, dynamic>;
      _manifest = raw.map((k, v) => MapEntry(k.toUpperCase(), v as String));

      for (final entry in _manifest.entries) {
        final data =
            await rootBundle.load('assets/sign_images/${entry.value}');
        _imageCache[entry.key] = data.buffer.asUint8List();
      }

      _loaded = true;
    } catch (e) {
      _loadError = e.toString();
      _loaded = false;
    }
  }

  /// Converts [text] into an ordered list of [SignImageSegment]s.
  ///
  /// Words are separated by [SignImageSegment.wordSpace] markers.
  /// Characters with no corresponding sign image are silently skipped.
  ///
  /// Example: "HELP ME" → [H, E, L, P, <space>, M, E]
  List<SignImageSegment> textToSegments(String text) {
    final segments = <SignImageSegment>[];
    final words =
        text.toUpperCase().trim().split(RegExp(r'\s+'));

    for (var wi = 0; wi < words.length; wi++) {
      if (wi > 0) segments.add(const SignImageSegment.wordSpace());
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

  /// Fast Dart-based keyword extractor used when T5 is not ready.
  /// Strips stop-words (articles, prepositions, pronouns, auxiliaries)
  /// and returns the remaining content words joined by spaces.
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
}
