import 'dart:math';

import 'package:flutter/material.dart';

import '../models/tutorial_models.dart';
import '../services/tutorial_repository.dart';

// ─────────────────────────── lesson stage enum ───────────────────────────────
enum _LessonStage { learn, mcq, match, result }

// ─────────────────────────── screen ──────────────────────────────────────────
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
  String? _selectedMcqOption;
  bool _mcqPassed = false;

  // match stage state
  List<TutorialLesson> _matchPairs = const []; // 4 pairs
  List<int?> _leftConnected = [];   // index in _matchPairs that left[i] is matched to right slot
  List<int?> _rightConnected = [];  // index in _matchPairs that right[i] is matched to left slot
  int? _selectedLeft;
  int? _selectedRight;
  bool _matchChecked = false;
  bool _matchPassed = false;

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? TutorialRepository();
    _bootstrap();
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
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  TutorialProgress _ensureUnlockedDefaults(List<TutorialUnit> units, TutorialProgress p) {
    final unlocked = Map<String, int>.from(p.latestUnlockedByUnit);
    for (final unit in units) {
      if (unit.lessons.isNotEmpty && !unlocked.containsKey(unit.id)) {
        unlocked[unit.id] = 0;
      }
    }
    return p.copyWith(latestUnlockedByUnit: unlocked);
  }

  bool _isLessonUnlocked(TutorialUnit unit, int index) {
    final idx = _progress.latestUnlockedByUnit[unit.id] ?? 0;
    return index <= idx;
  }

  // ── lesson start ────────────────────────────────────────────────────────────
  Future<void> _startLesson(TutorialLesson lesson) async {
    final unit = _units.firstWhere((u) => u.id == lesson.unitId);
    final lessonIndex = unit.lessons.indexWhere((l) => l.id == lesson.id);
    if (lessonIndex < 0 || !_isLessonUnlocked(unit, lessonIndex)) return;

    final pool = unit.lessons;
    final matchPairs = _buildMatchPairs(lesson: lesson, pool: pool);

    setState(() {
      _activeLesson = lesson;
      _stage = _LessonStage.learn;
      _mcqPassed = false;
      _selectedMcqOption = null;
      _mcqOptions = _repo.buildMcqOptions(lesson: lesson, pool: pool);
      _matchPairs = matchPairs;
      _leftConnected = List.filled(matchPairs.length, null);
      _rightConnected = List.filled(matchPairs.length, null);
      _selectedLeft = null;
      _selectedRight = null;
      _matchChecked = false;
      _matchPassed = false;
    });
  }

  // Build 4 pairs: current lesson + 3 random distractors from same unit
  List<TutorialLesson> _buildMatchPairs({
    required TutorialLesson lesson,
    required List<TutorialLesson> pool,
  }) {
    final rng = Random();
    final distractors = pool.where((l) => l.id != lesson.id).toList()..shuffle(rng);
    final pairs = <TutorialLesson>[lesson, ...distractors.take(3)];
    pairs.shuffle(rng);
    return pairs;
  }

  // ── stage transitions ────────────────────────────────────────────────────────
  void _advanceFromLearn() => setState(() => _stage = _LessonStage.mcq);

  void _submitMcq() {
    if (_selectedMcqOption == null || _activeLesson == null) return;
    _initMatchOrders();
    setState(() {
      _mcqPassed = _selectedMcqOption!.trim().toLowerCase() ==
          _activeLesson!.answer.toLowerCase();
      _stage = _LessonStage.match;
    });
  }

  // ── match stage interactions ─────────────────────────────────────────────────
  // Left column = shuffled sign images, Right column = shuffled word labels
  // We store two parallel lists: _leftOrder (indices into _matchPairs for images)
  // and _rightOrder (indices into _matchPairs for labels)
  late List<int> _leftOrder;
  late List<int> _rightOrder;

  void _initMatchOrders() {
    final rng = Random();
    _leftOrder = List.generate(_matchPairs.length, (i) => i)..shuffle(rng);
    _rightOrder = List.generate(_matchPairs.length, (i) => i)..shuffle(rng);
  }

  void _onLeftTap(int leftSlot) {
    if (_matchChecked) return;
    setState(() {
      if (_selectedLeft == leftSlot) {
        _selectedLeft = null;
      } else {
        _selectedLeft = leftSlot;
        if (_selectedRight != null) _tryConnect();
      }
    });
  }

  void _onRightTap(int rightSlot) {
    if (_matchChecked) return;
    setState(() {
      if (_selectedRight == rightSlot) {
        _selectedRight = null;
      } else {
        _selectedRight = rightSlot;
        if (_selectedLeft != null) _tryConnect();
      }
    });
  }

  void _tryConnect() {
    final ls = _selectedLeft!;
    final rs = _selectedRight!;

    // Remove any prior connections to these slots
    for (int i = 0; i < _matchPairs.length; i++) {
      if (_leftConnected[i] == rs) _leftConnected[i] = null;
      if (_rightConnected[i] == ls) _rightConnected[i] = null;
    }
    if (_leftConnected[ls] != null) {
      final prev = _leftConnected[ls]!;
      _rightConnected[prev] = null;
    }
    if (_rightConnected[rs] != null) {
      final prev = _rightConnected[rs]!;
      _leftConnected[prev] = null;
    }

    _leftConnected[ls] = rs;
    _rightConnected[rs] = ls;
    _selectedLeft = null;
    _selectedRight = null;
  }

  void _checkMatch() {
    bool allConnected = _leftConnected.every((v) => v != null);
    if (!allConnected) return;

    bool allCorrect = true;
    for (int li = 0; li < _leftOrder.length; li++) {
      final ri = _leftConnected[li];
      if (ri == null) { allCorrect = false; break; }
      final leftPairIdx = _leftOrder[li];
      final rightPairIdx = _rightOrder[ri];
      if (leftPairIdx != rightPairIdx) { allCorrect = false; break; }
    }

    setState(() {
      _matchChecked = true;
      _matchPassed = allCorrect;
      _stage = _LessonStage.result;
    });

    if (_mcqPassed && allCorrect) {
      _markLessonCompleted(_activeLesson!);
    } else {
      final updated = _progress.copyWith(
        streak: 0,
        hearts: (_progress.hearts - 1).clamp(0, 5),
      );
      setState(() => _progress = updated);
      _repo.saveProgress(updated);
    }
  }

  // ── completion ───────────────────────────────────────────────────────────────
  Future<void> _markLessonCompleted(TutorialLesson lesson) async {
    final completed = Set<String>.from(_progress.completedLessonIds)..add(lesson.id);
    final unlocked = Map<String, int>.from(_progress.latestUnlockedByUnit);
    final unit = _units.firstWhere((u) => u.id == lesson.unitId);
    final idx = unit.lessons.indexWhere((l) => l.id == lesson.id);
    if (idx >= 0) {
      final cur = unlocked[lesson.unitId] ?? 0;
      unlocked[lesson.unitId] = idx + 1 > cur ? idx + 1 : cur;
    }

    final today = _todayString();
    final isNewDay = _progress.lastActiveDate != today;
    final newStreak = isNewDay ? _progress.streak + 1 : _progress.streak;
    final newDailyXp = isNewDay ? 10 : _progress.dailyXp + 10;

    final next = _progress.copyWith(
      completedLessonIds: completed,
      latestUnlockedByUnit: unlocked,
      streak: newStreak,
      xp: _progress.xp + 10,
      dailyXp: newDailyXp,
      lastActiveDate: today,
      hearts: (_progress.hearts + 1).clamp(0, 5),
    );
    setState(() => _progress = next);
    await _repo.saveProgress(next);
  }

  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _skipLessonForMissingAsset() async {
    final lesson = _activeLesson;
    if (lesson == null) return;
    final completed = Set<String>.from(_progress.completedLessonIds)..add(lesson.id);
    final unlocked = Map<String, int>.from(_progress.latestUnlockedByUnit);
    final unit = _units.firstWhere((u) => u.id == lesson.unitId);
    final idx = unit.lessons.indexWhere((l) => l.id == lesson.id);
    if (idx >= 0) {
      final cur = unlocked[lesson.unitId] ?? 0;
      unlocked[lesson.unitId] = idx + 1 > cur ? idx + 1 : cur;
    }
    final next = _progress.copyWith(
      completedLessonIds: completed,
      latestUnlockedByUnit: unlocked,
      streak: 0,
    );
    setState(() { _progress = next; _activeLesson = null; _stage = _LessonStage.learn; });
    await _repo.saveProgress(next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Asset missing — lesson skipped.')),
    );
  }

  void _closeLessonFlow() {
    setState(() {
      _activeLesson = null;
      _stage = _LessonStage.learn;
      _selectedMcqOption = null;
    });
  }

  // ── build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF58CC02)))
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white70)))
              : _activeLesson == null
                  ? _buildMapView()
                  : _buildLessonFlow(),
    );
  }

  // ────────────────────────── MAP VIEW ─────────────────────────────────────────
  Widget _buildMapView() {
    return Column(
      children: [
        _TopStatsBar(progress: _progress),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
            children: [
              for (int ui = 0; ui < _units.length; ui++) ...[
                _UnitBanner(unit: _units[ui]),
                const SizedBox(height: 16),
                _UnitPath(
                  unit: _units[ui],
                  progress: _progress,
                  onLessonTap: _startLesson,
                  isUnlocked: (unit, i) => _isLessonUnlocked(unit, i),
                ),
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ────────────────────────── LESSON FLOW ──────────────────────────────────────
  Widget _buildLessonFlow() {
    final lesson = _activeLesson!;
    return SafeArea(
      child: Column(
        children: [
          // top bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _closeLessonFlow,
                  child: const Icon(Icons.close_rounded, color: Color(0xFF8FA0A8), size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(child: _ProgressBar(stage: _stage)),
                const SizedBox(width: 12),
                Row(
                  children: List.generate(5, (i) => Icon(
                    Icons.favorite_rounded,
                    size: 20,
                    color: i < _progress.hearts
                        ? const Color(0xFFFF4B4B)
                        : const Color(0xFF2A3540),
                  )),
                ),
              ],
            ),
          ),
          Expanded(child: _buildStageContent(lesson)),
        ],
      ),
    );
  }

  Widget _buildStageContent(TutorialLesson lesson) {
    switch (_stage) {
      case _LessonStage.learn:
        return _LearnStage(
          lesson: lesson,
          onContinue: _advanceFromLearn,
          onSkip: _skipLessonForMissingAsset,
        );
      case _LessonStage.mcq:
        return _McqStage(
          lesson: lesson,
          options: _mcqOptions,
          selected: _selectedMcqOption,
          onSelect: (v) => setState(() => _selectedMcqOption = v),
          onSubmit: _submitMcq,
          onSkip: _skipLessonForMissingAsset,
        );
      case _LessonStage.match:
        return _MatchStage(
          pairs: _matchPairs,
          leftOrder: _leftOrder,
          rightOrder: _rightOrder,
          leftConnected: _leftConnected,
          rightConnected: _rightConnected,
          selectedLeft: _selectedLeft,
          selectedRight: _selectedRight,
          checked: _matchChecked,
          onLeftTap: _onLeftTap,
          onRightTap: _onRightTap,
          onCheck: _checkMatch,
        );
      case _LessonStage.result:
        final passed = _mcqPassed && _matchPassed;
        return _ResultStage(
          passed: passed,
          xpEarned: passed ? 10 : 0,
          answer: lesson.answer,
          onNext: _closeLessonFlow,
          onRetry: () => _startLesson(lesson),
        );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  TOP STATS BAR
// ═══════════════════════════════════════════════════════════════════════════════
class _TopStatsBar extends StatelessWidget {
  final TutorialProgress progress;
  const _TopStatsBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(
          children: [
            _StatChip(
              icon: Icons.local_fire_department_rounded,
              iconColor: const Color(0xFFFF9600),
              value: '${progress.streak}',
            ),
            const SizedBox(width: 10),
            _StatChip(
              icon: Icons.diamond_rounded,
              iconColor: const Color(0xFF1CB0F6),
              value: '${progress.xp}',
              label: 'XP',
            ),
            const SizedBox(width: 10),
            _StatChip(
              icon: Icons.bolt_rounded,
              iconColor: const Color(0xFFFFCC00),
              value: '${progress.dailyXp}',
              label: 'Today',
            ),
            const Spacer(),
            Row(
              children: List.generate(5, (i) => Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Icon(
                  Icons.favorite_rounded,
                  size: 22,
                  color: i < progress.hearts
                      ? const Color(0xFFFF4B4B)
                      : const Color(0xFF2A3540),
                ),
              )),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String? label;
  const _StatChip({required this.icon, required this.iconColor, required this.value, this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: 22),
        const SizedBox(width: 4),
        Text(
          label != null ? '$value $label' : value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  UNIT BANNER  (green "SECTION X, UNIT Y" strip)
// ═══════════════════════════════════════════════════════════════════════════════
class _UnitBanner extends StatelessWidget {
  final TutorialUnit unit;
  const _UnitBanner({required this.unit});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF58CC02),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              unit.id == 'unit_words' ? 'SECTION 1, UNIT 1' : 'SECTION 1, UNIT 2',
              style: const TextStyle(
                color: Color(0xFF2D7A00),
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              unit.title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  UNIT PATH  (staggered nodes like Duolingo)
// ═══════════════════════════════════════════════════════════════════════════════
class _UnitPath extends StatelessWidget {
  final TutorialUnit unit;
  final TutorialProgress progress;
  final void Function(TutorialLesson) onLessonTap;
  final bool Function(TutorialUnit, int) isUnlocked;

  const _UnitPath({
    required this.unit,
    required this.progress,
    required this.onLessonTap,
    required this.isUnlocked,
  });

  // Stagger pattern: center, left, right, center, left, right ...
  static const _offsets = [0.0, -0.28, 0.28, 0.0, -0.28, 0.28];

  @override
  Widget build(BuildContext context) {
    final lessons = unit.lessons;
    final screenW = MediaQuery.of(context).size.width;

    return Column(
      children: List.generate(lessons.length, (i) {
        final lesson = lessons[i];
        final unlocked = isUnlocked(unit, i);
        final done = progress.completedLessonIds.contains(lesson.id);
        final fraction = _offsets[i % _offsets.length];
        final offsetX = fraction * screenW * 0.35;

        // Every 5th node is a chest or character icon instead of star
        _NodeType nodeType = _NodeType.star;
        if ((i + 1) % 5 == 0) nodeType = _NodeType.chest;
        if ((i + 1) % 7 == 0) nodeType = _NodeType.character;

        return Transform.translate(
          offset: Offset(offsetX, 0),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: _PathNode(
              lesson: lesson,
              index: i,
              unlocked: unlocked,
              completed: done,
              nodeType: nodeType,
              onTap: unlocked ? () => onLessonTap(lesson) : null,
            ),
          ),
        );
      }),
    );
  }
}

enum _NodeType { star, chest, character }

class _PathNode extends StatelessWidget {
  final TutorialLesson lesson;
  final int index;
  final bool unlocked;
  final bool completed;
  final _NodeType nodeType;
  final VoidCallback? onTap;

  const _PathNode({
    required this.lesson,
    required this.index,
    required this.unlocked,
    required this.completed,
    required this.nodeType,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = unlocked && !completed;

    // Colors
    final bgColor = completed
        ? const Color(0xFF58CC02)
        : unlocked
            ? const Color(0xFF1F2F3A)
            : const Color(0xFF151F28);
    final borderColor = completed
        ? const Color(0xFF2D7A00)
        : unlocked
            ? const Color(0xFF2A5870)
            : const Color(0xFF1A2830);
    final iconColor = completed
        ? Colors.white
        : unlocked
            ? const Color(0xFF8FA0A8)
            : const Color(0xFF2A3540);

    Widget nodeIcon;
    switch (nodeType) {
      case _NodeType.chest:
        nodeIcon = Icon(Icons.cases_rounded, color: unlocked ? const Color(0xFF8B6914) : const Color(0xFF2A3540), size: 36);
        break;
      case _NodeType.character:
        nodeIcon = Icon(Icons.face_rounded, color: unlocked ? const Color(0xFF8FA0A8) : const Color(0xFF2A3540), size: 36);
        break;
      case _NodeType.star:
        nodeIcon = Icon(Icons.star_rounded, color: iconColor, size: 40);
        break;
    }

    final size = isActive ? 72.0 : 60.0;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer progress ring for active node
          if (isActive)
            Container(
              width: size + 12,
              height: size + 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF58CC02),
                  width: 3,
                  strokeAlign: BorderSide.strokeAlignOutside,
                ),
                color: Colors.transparent,
              ),
            ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
              border: Border.all(color: borderColor, width: 3),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: const Color(0xFF58CC02).withValues(alpha: 0.35),
                        blurRadius: 16,
                        spreadRadius: 2,
                      )
                    ]
                  : null,
            ),
            child: Center(child: nodeIcon),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  LESSON PROGRESS BAR
// ═══════════════════════════════════════════════════════════════════════════════
class _ProgressBar extends StatelessWidget {
  final _LessonStage stage;
  const _ProgressBar({required this.stage});

  double get _fraction {
    switch (stage) {
      case _LessonStage.learn:   return 0.0;
      case _LessonStage.mcq:     return 0.33;
      case _LessonStage.match:   return 0.66;
      case _LessonStage.result:  return 1.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: LinearProgressIndicator(
        value: _fraction,
        minHeight: 10,
        backgroundColor: const Color(0xFF1F2F3A),
        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF58CC02)),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  LEARN STAGE
// ═══════════════════════════════════════════════════════════════════════════════
class _LearnStage extends StatelessWidget {
  final TutorialLesson lesson;
  final VoidCallback onContinue;
  final VoidCallback onSkip;
  const _LearnStage({required this.lesson, required this.onContinue, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Learn this sign',
            style: TextStyle(color: Color(0xFFF3F7F1), fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 16),
          Expanded(child: _SignCard(lesson: lesson, onSkip: onSkip)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2B38),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF2A4050)),
            ),
            child: Row(
              children: [
                const Icon(Icons.volume_up_rounded, color: Color(0xFF58CC02), size: 24),
                const SizedBox(width: 10),
                Text(
                  lesson.answer.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFFF3F7F1),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _GreenButton(label: 'CONTINUE', onTap: onContinue),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  MCQ STAGE
// ═══════════════════════════════════════════════════════════════════════════════
class _McqStage extends StatelessWidget {
  final TutorialLesson lesson;
  final List<String> options;
  final String? selected;
  final ValueChanged<String> onSelect;
  final VoidCallback onSubmit;
  final VoidCallback onSkip;
  const _McqStage({
    required this.lesson, required this.options, required this.selected,
    required this.onSelect, required this.onSubmit, required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'What does this sign mean?',
            style: TextStyle(color: Color(0xFFF3F7F1), fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          SizedBox(height: 200, child: _SignCard(lesson: lesson, onSkip: onSkip)),
          const SizedBox(height: 16),
          ...options.map((opt) => _McqOptionTile(
            label: opt,
            selected: selected == opt,
            onTap: () => onSelect(opt),
          )),
          const Spacer(),
          _GreenButton(
            label: 'CHECK',
            onTap: selected == null ? null : onSubmit,
          ),
        ],
      ),
    );
  }
}

class _McqOptionTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _McqOptionTile({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF162B14) : const Color(0xFF1A2B38),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFF58CC02) : const Color(0xFF2A4050),
            width: 2,
          ),
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            color: selected ? const Color(0xFF58CC02) : const Color(0xFFF3F7F1),
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  MATCH STAGE  (left = sign images, right = word labels, tap to connect)
// ═══════════════════════════════════════════════════════════════════════════════
class _MatchStage extends StatelessWidget {
  final List<TutorialLesson> pairs;
  final List<int> leftOrder;
  final List<int> rightOrder;
  final List<int?> leftConnected;
  final List<int?> rightConnected;
  final int? selectedLeft;
  final int? selectedRight;
  final bool checked;
  final void Function(int) onLeftTap;
  final void Function(int) onRightTap;
  final VoidCallback onCheck;

  const _MatchStage({
    required this.pairs,
    required this.leftOrder,
    required this.rightOrder,
    required this.leftConnected,
    required this.rightConnected,
    required this.selectedLeft,
    required this.selectedRight,
    required this.checked,
    required this.onLeftTap,
    required this.onRightTap,
    required this.onCheck,
  });

  bool _isCorrectPair(int li, int ri) {
    return leftOrder[li] == rightOrder[ri];
  }

  Color _leftBorderColor(int li) {
    if (selectedLeft == li) return const Color(0xFF1CB0F6);
    final ri = leftConnected[li];
    if (ri == null) return const Color(0xFF2A4050);
    if (checked) return _isCorrectPair(li, ri) ? const Color(0xFF58CC02) : const Color(0xFFFF4B4B);
    return const Color(0xFFFFCC00);
  }

  Color _rightBorderColor(int ri) {
    if (selectedRight == ri) return const Color(0xFF1CB0F6);
    final li = rightConnected[ri];
    if (li == null) return const Color(0xFF2A4050);
    if (checked) return _isCorrectPair(li, ri) ? const Color(0xFF58CC02) : const Color(0xFFFF4B4B);
    return const Color(0xFFFFCC00);
  }

  @override
  Widget build(BuildContext context) {
    final allConnected = leftConnected.every((v) => v != null);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Match the signs',
            style: TextStyle(color: Color(0xFFF3F7F1), fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap a sign, then tap its matching word',
            style: TextStyle(color: Color(0xFF8FA0A8), fontSize: 13),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              children: [
                // LEFT: sign images
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(pairs.length, (li) {
                      final lesson = pairs[leftOrder[li]];
                      final borderColor = _leftBorderColor(li);
                      final isSelected = selectedLeft == li;
                      final isConnected = leftConnected[li] != null;

                      return GestureDetector(
                        onTap: () => onLeftTap(li),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: double.infinity,
                          height: 72,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF0D2033)
                                : isConnected
                                    ? const Color(0xFF172010)
                                    : const Color(0xFF1A2B38),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderColor, width: 2),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              lesson.assetPath,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Center(
                                child: Text(
                                  lesson.answer[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: Color(0xFF8FA0A8),
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                // RIGHT: word labels
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(pairs.length, (ri) {
                      final lesson = pairs[rightOrder[ri]];
                      final borderColor = _rightBorderColor(ri);
                      final isSelected = selectedRight == ri;
                      final isConnected = rightConnected[ri] != null;

                      return GestureDetector(
                        onTap: () => onRightTap(ri),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: double.infinity,
                          height: 72,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF0D2033)
                                : isConnected
                                    ? const Color(0xFF172010)
                                    : const Color(0xFF1A2B38),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderColor, width: 2),
                          ),
                          child: Center(
                            child: Text(
                              lesson.answer.toUpperCase(),
                              style: const TextStyle(
                                color: Color(0xFFF3F7F1),
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _GreenButton(
            label: 'CHECK',
            onTap: allConnected && !checked ? onCheck : null,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  RESULT STAGE
// ═══════════════════════════════════════════════════════════════════════════════
class _ResultStage extends StatelessWidget {
  final bool passed;
  final int xpEarned;
  final String answer;
  final VoidCallback onNext;
  final VoidCallback onRetry;
  const _ResultStage({
    required this.passed, required this.xpEarned,
    required this.answer, required this.onNext, required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // big icon
          Icon(
            passed ? Icons.emoji_events_rounded : Icons.sentiment_dissatisfied_rounded,
            size: 80,
            color: passed ? const Color(0xFFFFCC00) : const Color(0xFFFF4B4B),
          ),
          const SizedBox(height: 16),
          Text(
            passed ? 'Lesson Complete!' : 'Keep Practicing!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: passed ? const Color(0xFF58CC02) : const Color(0xFFFF4B4B),
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Answer: ${answer.toUpperCase()}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF8FA0A8), fontSize: 16, fontWeight: FontWeight.w700),
          ),
          if (passed) ...[
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF162B14),
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(color: const Color(0xFF58CC02), width: 2),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.diamond_rounded, color: Color(0xFF1CB0F6), size: 22),
                      const SizedBox(width: 6),
                      Text(
                        '+$xpEarned XP',
                        style: const TextStyle(
                          color: Color(0xFF58CC02),
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 32),
          _GreenButton(
            label: passed ? 'CONTINUE' : 'TRY AGAIN',
            onTap: passed ? onNext : onRetry,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  SIGN CARD  (image display with error fallback)
// ═══════════════════════════════════════════════════════════════════════════════
class _SignCard extends StatelessWidget {
  final TutorialLesson lesson;
  final VoidCallback onSkip;
  const _SignCard({required this.lesson, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A2B38),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2A4050), width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.asset(
          lesson.assetPath,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.broken_image_rounded, color: Color(0xFF8FA0A8), size: 48),
                const SizedBox(height: 8),
                const Text('Asset unavailable', style: TextStyle(color: Color(0xFF8FA0A8))),
                const SizedBox(height: 10),
                TextButton(onPressed: onSkip, child: const Text('SKIP')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  GREEN BUTTON
// ═══════════════════════════════════════════════════════════════════════════════
class _GreenButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _GreenButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 52,
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFF58CC02) : const Color(0xFF1F2F3A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: enabled ? const Color(0xFF45A300) : const Color(0xFF2A4050),
            width: 2,
          ),
          boxShadow: enabled
              ? [const BoxShadow(color: Color(0x4458CC02), blurRadius: 8, offset: Offset(0, 4))]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: enabled ? Colors.white : const Color(0xFF4A5568),
              fontWeight: FontWeight.w900,
              fontSize: 16,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }
}
