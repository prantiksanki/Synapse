import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synapse/models/tutorial_models.dart';
import 'package:synapse/services/tutorial_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builds curriculum from asset manifest and sign image manifest', () async {
    final repo = TutorialRepository(
      random: Random(7),
      loadString: (path) async {
        if (path == 'AssetManifest.json') {
          return ''']
          {
            "assets/sign_videos/Hello.gif": [],
            "assets/sign_videos/Water.gif": [],
            "assets/sign_images/A.png": [],
            "assets/sign_images/1.png": []
          }
          ''';
        }
        if (path == 'assets/sign_images/manifest.json') {
          return '''
          {
            "A": "A.png",
            "1": "1.png"
          }
          ''';
        }
        throw StateError('Unexpected path: $path');
      },
      prefsFactory: () => SharedPreferences.getInstance(),
    );

    final units = await repo.loadCurriculum();

    expect(units.length, 2);
    expect(units[0].id, 'unit_words');
    expect(units[0].lessons.map((e) => e.answer), ['hello', 'water']);
    expect(units[1].id, 'unit_symbols');
    expect(units[1].lessons.map((e) => e.answer), ['1', 'a']);
  });

  test('mcq options include correct answer and no duplicates', () async {
    final repo = TutorialRepository(random: Random(1));
    const lessonA = (
      id: 'word_hello',
      answer: 'hello',
    );
    const lessonB = (
      id: 'word_water',
      answer: 'water',
    );
    const lessonC = (
      id: 'word_food',
      answer: 'food',
    );
    const lessonD = (
      id: 'word_need',
      answer: 'need',
    );
    final pool = [
      _fakeLesson(lessonA.id, lessonA.answer),
      _fakeLesson(lessonB.id, lessonB.answer),
      _fakeLesson(lessonC.id, lessonC.answer),
      _fakeLesson(lessonD.id, lessonD.answer),
    ];

    final options = repo.buildMcqOptions(
      lesson: pool.first,
      pool: pool,
    );

    expect(options.length, 4);
    expect(options.toSet().length, 4);
    expect(options, contains('hello'));
  });

  test('progress save/load roundtrip works', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = TutorialRepository(prefsFactory: SharedPreferences.getInstance);

    final original = _fakeProgress();
    await repo.saveProgress(original);
    final loaded = await repo.loadProgress();

    expect(loaded.completedLessonIds, original.completedLessonIds);
    expect(loaded.latestUnlockedByUnit, original.latestUnlockedByUnit);
    expect(loaded.streak, original.streak);
    expect(loaded.xp, original.xp);
  });
}

_fakeLesson(String id, String answer) => TutorialLesson(
      id: id,
      unitId: 'unit_words',
      type: TutorialLessonType.wordGif,
      prompt: 'Learn this sign word',
      answer: answer,
      assetPath: 'assets/sign_videos/$answer.gif',
    );

TutorialProgress _fakeProgress() {
  return const TutorialProgress(
    completedLessonIds: {'word_hello', 'word_water'},
    latestUnlockedByUnit: {'unit_words': 2, 'unit_symbols': 1},
    streak: 4,
    xp: 120,
  );
}
