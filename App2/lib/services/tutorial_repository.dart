import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/tutorial_models.dart';

abstract class TutorialDataSource {
  Future<List<TutorialUnit>> loadCurriculum();
  Future<TutorialProgress> loadProgress();
  Future<void> saveProgress(TutorialProgress progress);
  List<String> buildMcqOptions({
    required TutorialLesson lesson,
    required List<TutorialLesson> pool,
    int optionCount,
  });
}

class TutorialRepository implements TutorialDataSource {
  static const _completedKey = 'tutorial_completed_lessons';
  static const _unlockedMapKey = 'tutorial_latest_unlocked_by_unit';
  static const _streakKey = 'tutorial_streak';
  static const _xpKey = 'tutorial_xp';
  static const _dailyXpKey = 'tutorial_daily_xp';
  static const _lastActiveDateKey = 'tutorial_last_active_date';
  static const _heartsKey = 'tutorial_hearts';

  final Future<String> Function(String path) _loadString;
  final Future<SharedPreferences> Function() _prefsFactory;
  final Random _random;

  TutorialRepository({
    Future<String> Function(String path)? loadString,
    Future<SharedPreferences> Function()? prefsFactory,
    Random? random,
  })  : _loadString = loadString ?? rootBundle.loadString,
        _prefsFactory = prefsFactory ?? SharedPreferences.getInstance,
        _random = random ?? Random();

  @override
  Future<List<TutorialUnit>> loadCurriculum() async {
    final assetManifest = await _loadAssetManifest();
    final gifLessons = _buildGifLessons(assetManifest);
    final symbolLessons = await _buildSymbolLessons();

    return [
      TutorialUnit(id: 'unit_words', title: 'Word Signs', lessons: gifLessons),
      TutorialUnit(
        id: 'unit_symbols',
        title: 'Alphabet & Numbers',
        lessons: symbolLessons,
      ),
    ];
  }

  @override
  Future<TutorialProgress> loadProgress() async {
    final prefs = await _prefsFactory();
    final completed = prefs.getStringList(_completedKey) ?? const <String>[];
    final unlockedJson = prefs.getString(_unlockedMapKey);
    final unlocked = <String, int>{};
    if (unlockedJson != null && unlockedJson.isNotEmpty) {
      final raw = jsonDecode(unlockedJson);
      if (raw is Map<String, dynamic>) {
        for (final entry in raw.entries) {
          final value = entry.value;
          if (value is num) {
            unlocked[entry.key] = value.toInt();
          }
        }
      }
    }

    final today = _todayString();
    final lastDate = prefs.getString(_lastActiveDateKey) ?? '';
    final dailyXp = lastDate == today ? (prefs.getInt(_dailyXpKey) ?? 0) : 0;

    return TutorialProgress(
      completedLessonIds: completed.toSet(),
      latestUnlockedByUnit: unlocked,
      streak: prefs.getInt(_streakKey) ?? 0,
      xp: prefs.getInt(_xpKey) ?? 0,
      dailyXp: dailyXp,
      lastActiveDate: lastDate,
      hearts: prefs.getInt(_heartsKey) ?? 5,
    );
  }

  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  Future<void> saveProgress(TutorialProgress progress) async {
    final prefs = await _prefsFactory();
    await prefs.setStringList(
      _completedKey,
      progress.completedLessonIds.toList()..sort(),
    );
    await prefs.setString(_unlockedMapKey, jsonEncode(progress.latestUnlockedByUnit));
    await prefs.setInt(_streakKey, progress.streak);
    await prefs.setInt(_xpKey, progress.xp);
    await prefs.setInt(_dailyXpKey, progress.dailyXp);
    await prefs.setString(_lastActiveDateKey, progress.lastActiveDate);
    await prefs.setInt(_heartsKey, progress.hearts);
  }

  @override
  List<String> buildMcqOptions({
    required TutorialLesson lesson,
    required List<TutorialLesson> pool,
    int optionCount = 4,
  }) {
    final distinctAnswers = pool
        .map((e) => e.answer)
        .where((e) => e.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final options = <String>{lesson.answer};
    final distractors = distinctAnswers.where((e) => e != lesson.answer).toList();
    while (options.length < optionCount && distractors.isNotEmpty) {
      final index = _random.nextInt(distractors.length);
      options.add(distractors.removeAt(index));
    }
    final shuffled = options.toList()..shuffle(_random);
    return shuffled;
  }

  Future<Map<String, dynamic>> _loadAssetManifest() async {
    final assetManifestJson = await _loadString('AssetManifest.json');
    final raw = jsonDecode(assetManifestJson);
    if (raw is! Map<String, dynamic>) return <String, dynamic>{};
    return raw;
  }

  List<TutorialLesson> _buildGifLessons(Map<String, dynamic> assetManifest) {
    final gifAssets = assetManifest.keys
        .where(
          (path) =>
              path.startsWith('assets/sign_videos/') &&
              path.toLowerCase().endsWith('.gif'),
        )
        .toList()
      ..sort();

    return List<TutorialLesson>.generate(gifAssets.length, (i) {
      final assetPath = gifAssets[i];
      final fileName = assetPath.split('/').last;
      final answer = fileName.replaceAll(RegExp(r'\.[^.]+$'), '').toLowerCase();
      return TutorialLesson(
        id: 'word_$answer',
        unitId: 'unit_words',
        type: TutorialLessonType.wordGif,
        prompt: 'Learn this sign word',
        answer: answer,
        assetPath: assetPath,
      );
    });
  }

  Future<List<TutorialLesson>> _buildSymbolLessons() async {
    final manifestJson = await _loadString('assets/sign_images/manifest.json');
    final raw = jsonDecode(manifestJson);
    if (raw is! Map<String, dynamic>) return const [];

    final entries = raw.entries
        .where((e) => e.value is String)
        .map((e) => MapEntry(e.key.toUpperCase(), e.value as String))
        .toList()
      ..sort((a, b) {
        final aNum = int.tryParse(a.key);
        final bNum = int.tryParse(b.key);
        if (aNum != null && bNum != null) return aNum.compareTo(bNum);
        if (aNum != null) return -1;
        if (bNum != null) return 1;
        return a.key.compareTo(b.key);
      });

    return List<TutorialLesson>.generate(entries.length, (i) {
      final symbol = entries[i].key;
      return TutorialLesson(
        id: 'symbol_$symbol',
        unitId: 'unit_symbols',
        type: TutorialLessonType.symbolImage,
        prompt: 'Learn this hand symbol',
        answer: symbol.toLowerCase(),
        assetPath: 'assets/sign_images/${entries[i].value}',
      );
    });
  }
}
