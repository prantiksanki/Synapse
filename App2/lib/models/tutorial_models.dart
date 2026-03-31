enum TutorialLessonType { wordGif, symbolImage }

class TutorialLesson {
  final String id;
  final String unitId;
  final TutorialLessonType type;
  final String prompt;
  final String answer;
  final String assetPath;

  const TutorialLesson({
    required this.id,
    required this.unitId,
    required this.type,
    required this.prompt,
    required this.answer,
    required this.assetPath,
  });
}

class TutorialUnit {
  final String id;
  final String title;
  final List<TutorialLesson> lessons;

  const TutorialUnit({
    required this.id,
    required this.title,
    required this.lessons,
  });
}

class TutorialProgress {
  final Set<String> completedLessonIds;
  final Map<String, int> latestUnlockedByUnit;
  final int streak;
  final int xp;

  const TutorialProgress({
    required this.completedLessonIds,
    required this.latestUnlockedByUnit,
    required this.streak,
    required this.xp,
  });

  factory TutorialProgress.initial() {
    return const TutorialProgress(
      completedLessonIds: <String>{},
      latestUnlockedByUnit: {},
      streak: 0,
      xp: 0,
    );
  }

  TutorialProgress copyWith({
    Set<String>? completedLessonIds,
    Map<String, int>? latestUnlockedByUnit,
    int? streak,
    int? xp,
  }) {
    return TutorialProgress(
      completedLessonIds: completedLessonIds ?? this.completedLessonIds,
      latestUnlockedByUnit: latestUnlockedByUnit ?? this.latestUnlockedByUnit,
      streak: streak ?? this.streak,
      xp: xp ?? this.xp,
    );
  }
}
