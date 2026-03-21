class WordBufferState {
  final List<String> activeTokens;
  final String lastCommittedPhrase;
  final String? lastStableLabel;
  final bool isBoundaryReady;

  const WordBufferState({
    required this.activeTokens,
    required this.lastCommittedPhrase,
    required this.lastStableLabel,
    required this.isBoundaryReady,
  });

  const WordBufferState.initial()
      : activeTokens = const [],
        lastCommittedPhrase = '',
        lastStableLabel = null,
        isBoundaryReady = false;

  String get activePhrase => activeTokens.join(' ');
}
