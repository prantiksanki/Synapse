import 'package:flutter/material.dart';

import '../models/tutorial_models.dart';
import '../services/tutorial_repository.dart';

enum _LessonStage { learn, mcq, typing, result }

class TutorialScreen extends StatefulWidget {
  final TutorialDataSource? repository;

  const TutorialScreen({super.key, this.repository});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  late final TutorialDataSource _repo;
  List<TutorialUnit> _units = const [];
  TutorialProgress _progress = TutorialProgress.initial();

  bool _loading = true;
  String? _error;

  TutorialLesson? _activeLesson;
  _LessonStage _stage = _LessonStage.learn;
  List<String> _mcqOptions = const [];
  String? _selectedOption;
  final TextEditingController _typingController = TextEditingController();
  bool _mcqPassed = false;
  bool _typingPassed = false;

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? TutorialRepository();
    _bootstrap();
  }

  @override
  void dispose() {
    _typingController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final units = await _repo.loadCurriculum();
      final progress = await _repo.loadProgress();
      if (!mounted) return;
      setState(() {
        _units = units;
        _progress = _ensureUnlockedDefaults(units, progress);
        _loading = false;
      });
      await _repo.saveProgress(_progress);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  TutorialProgress _ensureUnlockedDefaults(
    List<TutorialUnit> units,
    TutorialProgress progress,
  ) {
    final unlocked = Map<String, int>.from(progress.latestUnlockedByUnit);
    for (final unit in units) {
      if (unit.lessons.isNotEmpty && !unlocked.containsKey(unit.id)) {
        unlocked[unit.id] = 0;
      }
    }
    return progress.copyWith(latestUnlockedByUnit: unlocked);
  }

  bool _isLessonUnlocked(TutorialUnit unit, int index) {
    final unlockedIdx = _progress.latestUnlockedByUnit[unit.id] ?? 0;
    return index <= unlockedIdx;
  }

  Future<void> _startLesson(TutorialLesson lesson) async {
    final unit = _units.firstWhere((u) => u.id == lesson.unitId);
    final lessonIndex = unit.lessons.indexWhere((l) => l.id == lesson.id);
    if (lessonIndex < 0 || !_isLessonUnlocked(unit, lessonIndex)) return;

    final pool = unit.lessons;
    setState(() {
      _activeLesson = lesson;
      _stage = _LessonStage.learn;
      _mcqPassed = false;
      _typingPassed = false;
      _selectedOption = null;
      _typingController.clear();
      _mcqOptions = _repo.buildMcqOptions(lesson: lesson, pool: pool);
    });
  }

  void _advanceFromLearn() {
    setState(() => _stage = _LessonStage.mcq);
  }

  void _submitMcq() {
    if (_selectedOption == null || _activeLesson == null) return;
    setState(() {
      _mcqPassed =
          _selectedOption!.trim().toLowerCase() == _activeLesson!.answer.toLowerCase();
      _stage = _LessonStage.typing;
    });
  }

  Future<void> _submitTyping() async {
    if (_activeLesson == null) return;
    final typed = _typingController.text.trim().toLowerCase();
    final answer = _activeLesson!.answer.toLowerCase();
    final passed = typed == answer;

    setState(() {
      _typingPassed = passed;
      _stage = _LessonStage.result;
    });

    if (_mcqPassed && passed) {
      await _markLessonCompleted(_activeLesson!);
    } else {
      final updated = _progress.copyWith(streak: 0);
      setState(() => _progress = updated);
      await _repo.saveProgress(updated);
    }
  }

  Future<void> _markLessonCompleted(TutorialLesson lesson) async {
    final completed = Set<String>.from(_progress.completedLessonIds)..add(lesson.id);
    final unlocked = Map<String, int>.from(_progress.latestUnlockedByUnit);
    final unit = _units.firstWhere((u) => u.id == lesson.unitId);
    final idx = unit.lessons.indexWhere((l) => l.id == lesson.id);
    if (idx >= 0) {
      final current = unlocked[lesson.unitId] ?? 0;
      unlocked[lesson.unitId] = idx + 1 > current ? idx + 1 : current;
    }

    final nextProgress = _progress.copyWith(
      completedLessonIds: completed,
      latestUnlockedByUnit: unlocked,
      streak: _progress.streak + 1,
      xp: _progress.xp + 10,
    );
    setState(() => _progress = nextProgress);
    await _repo.saveProgress(nextProgress);
  }

  Future<void> _skipLessonForMissingAsset() async {
    final lesson = _activeLesson;
    if (lesson == null) return;

    final completed = Set<String>.from(_progress.completedLessonIds)..add(lesson.id);
    final unlocked = Map<String, int>.from(_progress.latestUnlockedByUnit);
    final unit = _units.firstWhere((u) => u.id == lesson.unitId);
    final idx = unit.lessons.indexWhere((l) => l.id == lesson.id);
    if (idx >= 0) {
      final current = unlocked[lesson.unitId] ?? 0;
      unlocked[lesson.unitId] = idx + 1 > current ? idx + 1 : current;
    }

    final nextProgress = _progress.copyWith(
      completedLessonIds: completed,
      latestUnlockedByUnit: unlocked,
      streak: 0,
    );
    setState(() {
      _progress = nextProgress;
      _activeLesson = null;
      _stage = _LessonStage.learn;
    });
    await _repo.saveProgress(nextProgress);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Asset missing. Lesson skipped and next lesson unlocked.'),
      ),
    );
  }

  void _closeLessonFlow() {
    setState(() {
      _activeLesson = null;
      _stage = _LessonStage.learn;
      _selectedOption = null;
      _typingController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF11181C),
      appBar: AppBar(
        title: const Text('Sign Tutorial'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _activeLesson == null
                  ? _buildCurriculumView()
                  : _buildLessonFlow(),
    );
  }

  Widget _buildCurriculumView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
      children: [
        _StatsCard(progress: _progress),
        const SizedBox(height: 18),
        for (final unit in _units) ...[
          Text(
            unit.title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Color(0xFFF3F7F1),
            ),
          ),
          const SizedBox(height: 10),
          ...List.generate(unit.lessons.length, (i) {
            final lesson = unit.lessons[i];
            final unlocked = _isLessonUnlocked(unit, i);
            final done = _progress.completedLessonIds.contains(lesson.id);
            return _LessonTile(
              lesson: lesson,
              index: i + 1,
              unlocked: unlocked,
              completed: done,
              onTap: unlocked ? () => _startLesson(lesson) : null,
            );
          }),
          const SizedBox(height: 18),
        ],
      ],
    );
  }

  Widget _buildLessonFlow() {
    final lesson = _activeLesson!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: _closeLessonFlow,
                icon: const Icon(Icons.close_rounded),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  lesson.prompt,
                  style: const TextStyle(
                    color: Color(0xFFF3F7F1),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _buildStageContent(lesson),
          ),
        ],
      ),
    );
  }

  Widget _buildStageContent(TutorialLesson lesson) {
    switch (_stage) {
      case _LessonStage.learn:
        return _LearnStageCard(
          lesson: lesson,
          onContinue: _advanceFromLearn,
          onSkip: _skipLessonForMissingAsset,
        );
      case _LessonStage.mcq:
        return _McqStageCard(
          lesson: lesson,
          options: _mcqOptions,
          selected: _selectedOption,
          onSelect: (value) => setState(() => _selectedOption = value),
          onSubmit: _submitMcq,
          onSkip: _skipLessonForMissingAsset,
        );
      case _LessonStage.typing:
        return _TypingStageCard(
          lesson: lesson,
          controller: _typingController,
          onSubmit: _submitTyping,
          onSkip: _skipLessonForMissingAsset,
        );
      case _LessonStage.result:
        final passed = _mcqPassed && _typingPassed;
        return _ResultStageCard(
          passed: passed,
          answer: lesson.answer,
          onNext: _closeLessonFlow,
          onRetry: () => _startLesson(lesson),
        );
    }
  }
}

class _StatsCard extends StatelessWidget {
  final TutorialProgress progress;
  const _StatsCard({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF182227),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF33434C), width: 2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatCell(label: 'XP', value: '${progress.xp}'),
          _StatCell(label: 'Streak', value: '${progress.streak}'),
          _StatCell(label: 'Done', value: '${progress.completedLessonIds.length}'),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  const _StatCell({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Color(0xFF95DE28), fontWeight: FontWeight.w900, fontSize: 20)),
        Text(label, style: const TextStyle(color: Color(0xFF8FA0A8), fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _LessonTile extends StatelessWidget {
  final TutorialLesson lesson;
  final int index;
  final bool unlocked;
  final bool completed;
  final VoidCallback? onTap;

  const _LessonTile({
    required this.lesson,
    required this.index,
    required this.unlocked,
    required this.completed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: unlocked ? 1 : 0.55,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF11181C),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: completed ? const Color(0xFF95DE28) : const Color(0xFF33434C),
            width: 2,
          ),
        ),
        child: ListTile(
          onTap: onTap,
          leading: CircleAvatar(
            backgroundColor: completed ? const Color(0xFF95DE28) : const Color(0xFF1D282D),
            child: Text('$index', style: TextStyle(color: completed ? const Color(0xFF13210B) : const Color(0xFFF3F7F1), fontWeight: FontWeight.w800)),
          ),
          title: Text(
            lesson.answer.toUpperCase(),
            style: const TextStyle(color: Color(0xFFF3F7F1), fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            unlocked ? (completed ? 'Completed' : 'Ready') : 'Locked',
            style: const TextStyle(color: Color(0xFF8FA0A8)),
          ),
          trailing: Icon(
            unlocked ? Icons.play_arrow_rounded : Icons.lock_rounded,
            color: unlocked ? const Color(0xFF95DE28) : const Color(0xFF8FA0A8),
          ),
        ),
      ),
    );
  }
}

class _LearnStageCard extends StatelessWidget {
  final TutorialLesson lesson;
  final VoidCallback onContinue;
  final VoidCallback onSkip;

  const _LearnStageCard({
    required this.lesson,
    required this.onContinue,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _SignVisualCard(lesson: lesson, onSkip: onSkip)),
        const SizedBox(height: 12),
        Text(
          'Meaning: ${lesson.answer}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFF3F7F1), fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        ElevatedButton(onPressed: onContinue, child: const Text('CONTINUE')),
      ],
    );
  }
}

class _McqStageCard extends StatelessWidget {
  final TutorialLesson lesson;
  final List<String> options;
  final String? selected;
  final ValueChanged<String> onSelect;
  final VoidCallback onSubmit;
  final VoidCallback onSkip;

  const _McqStageCard({
    required this.lesson,
    required this.options,
    required this.selected,
    required this.onSelect,
    required this.onSubmit,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _SignVisualCard(lesson: lesson, onSkip: onSkip)),
        const SizedBox(height: 12),
        const Text(
          'What does this sign mean?',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFF3F7F1), fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        for (final option in options)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              onPressed: () => onSelect(option),
              style: OutlinedButton.styleFrom(
                backgroundColor: selected == option ? const Color(0xFF182B14) : null,
                side: BorderSide(
                  color: selected == option ? const Color(0xFF95DE28) : const Color(0xFF33434C),
                  width: 2,
                ),
              ),
              child: Text(option.toUpperCase()),
            ),
          ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: selected == null ? null : onSubmit,
          child: const Text('SUBMIT'),
        ),
      ],
    );
  }
}

class _TypingStageCard extends StatelessWidget {
  final TutorialLesson lesson;
  final TextEditingController controller;
  final VoidCallback onSubmit;
  final VoidCallback onSkip;
  const _TypingStageCard({
    required this.lesson,
    required this.controller,
    required this.onSubmit,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _SignVisualCard(lesson: lesson, onSkip: onSkip)),
        const SizedBox(height: 12),
        const Text(
          'Type the answer',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFF3F7F1), fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSubmit(),
          decoration: const InputDecoration(hintText: 'Enter meaning'),
        ),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: onSubmit, child: const Text('CHECK')),
      ],
    );
  }
}

class _ResultStageCard extends StatelessWidget {
  final bool passed;
  final String answer;
  final VoidCallback onNext;
  final VoidCallback onRetry;

  const _ResultStageCard({
    required this.passed,
    required this.answer,
    required this.onNext,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF182227),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: passed ? const Color(0xFF95DE28) : const Color(0xFFEF4444),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              passed ? Icons.emoji_events_rounded : Icons.refresh_rounded,
              color: passed ? const Color(0xFF95DE28) : const Color(0xFFEF4444),
              size: 56,
            ),
            const SizedBox(height: 12),
            Text(
              passed ? 'Great! Lesson Cleared' : 'Not Yet, Try Again',
              style: const TextStyle(color: Color(0xFFF3F7F1), fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              'Answer: ${answer.toUpperCase()}',
              style: const TextStyle(color: Color(0xFF8FA0A8), fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: passed ? onNext : onRetry,
              child: Text(passed ? 'BACK TO LESSONS' : 'RETRY'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignVisualCard extends StatelessWidget {
  final TutorialLesson lesson;
  final VoidCallback onSkip;

  const _SignVisualCard({
    required this.lesson,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF182227),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF33434C), width: 2),
      ),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Image.asset(
          lesson.assetPath,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.broken_image_rounded, color: Color(0xFF8FA0A8), size: 48),
                const SizedBox(height: 8),
                Text(
                  'Asset unavailable. You can continue.',
                  style: TextStyle(color: Color(0xFF8FA0A8)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: onSkip,
                  child: const Text('SKIP LESSON'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
