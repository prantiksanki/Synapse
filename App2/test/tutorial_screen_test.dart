import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synapse/models/tutorial_models.dart';
import 'package:synapse/screens/tutorial_screen.dart';
import 'package:synapse/services/tutorial_repository.dart';

void main() {
  testWidgets('lesson flow goes Learn -> MCQ -> Typing -> Result', (
    tester,
  ) async {
    final repo = _FakeTutorialRepo();
    await tester.pumpWidget(
      MaterialApp(
        home: TutorialScreen(repository: repo),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Word Signs'), findsOneWidget);
    await tester.tap(find.text('HELLO'));
    await tester.pumpAndSettle();

    expect(find.text('Meaning: hello'), findsOneWidget);
    await tester.tap(find.text('CONTINUE'));
    await tester.pumpAndSettle();

    expect(find.text('What does this sign mean?'), findsOneWidget);
    await tester.tap(find.text('HELLO'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SUBMIT'));
    await tester.pumpAndSettle();

    expect(find.text('Type the answer'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.tap(find.text('CHECK'));
    await tester.pumpAndSettle();

    expect(find.text('Great! Lesson Cleared'), findsOneWidget);
    expect(find.text('BACK TO LESSONS'), findsOneWidget);
  });

  testWidgets('failed typing keeps lesson retry state', (tester) async {
    final repo = _FakeTutorialRepo();
    await tester.pumpWidget(
      MaterialApp(
        home: TutorialScreen(repository: repo),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('HELLO'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONTINUE'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('HELLO'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SUBMIT'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.tap(find.text('CHECK'));
    await tester.pumpAndSettle();

    expect(find.text('Not Yet, Try Again'), findsOneWidget);
    expect(find.text('RETRY'), findsOneWidget);
  });
}

class _FakeTutorialRepo implements TutorialDataSource {
  TutorialProgress _progress = TutorialProgress.initial().copyWith(
    latestUnlockedByUnit: {'unit_words': 0, 'unit_symbols': 0},
  );

  @override
  List<String> buildMcqOptions({
    required TutorialLesson lesson,
    required List<TutorialLesson> pool,
    int optionCount = 4,
  }) {
    return ['hello', 'water', 'food', 'need'];
  }

  @override
  Future<List<TutorialUnit>> loadCurriculum() async {
    return [
      TutorialUnit(
        id: 'unit_words',
        title: 'Word Signs',
        lessons: const [
          TutorialLesson(
            id: 'word_hello',
            unitId: 'unit_words',
            type: TutorialLessonType.wordGif,
            prompt: 'Learn this sign word',
            answer: 'hello',
            assetPath: 'assets/sign_videos/Hello.gif',
          ),
        ],
      ),
      TutorialUnit(
        id: 'unit_symbols',
        title: 'Alphabet & Numbers',
        lessons: const [
          TutorialLesson(
            id: 'symbol_a',
            unitId: 'unit_symbols',
            type: TutorialLessonType.symbolImage,
            prompt: 'Learn this hand symbol',
            answer: 'a',
            assetPath: 'assets/sign_images/A.png',
          ),
        ],
      ),
    ];
  }

  @override
  Future<TutorialProgress> loadProgress() async => _progress;

  @override
  Future<void> saveProgress(TutorialProgress progress) async {
    _progress = progress;
  }
}
