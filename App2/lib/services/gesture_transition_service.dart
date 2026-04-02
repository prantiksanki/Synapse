import '../config/app_config.dart';
import '../models/gesture_result.dart';

/// Filters transient label changes while the user moves between signs.
///
/// A new label must stay stable for [AppConfig.gestureStabilizationDelay], and
/// accepted labels are separated by at least
/// [AppConfig.gestureTransitionDelay].
class GestureTransitionService {
  GestureResult? _pendingGesture;
  DateTime? _pendingGestureSince;

  void reset() {
    _pendingGesture = null;
    _pendingGestureSince = null;
  }

  GestureResult? acceptStableGesture({
    required GestureResult candidate,
    required String? currentLabel,
    required DateTime now,
    required DateTime? lastAcceptedAt,
  }) {
    if (currentLabel == candidate.label) {
      reset();
      return candidate;
    }

    if (_pendingGesture == null || _pendingGesture!.label != candidate.label) {
      _pendingGesture = candidate;
      _pendingGestureSince = now;
      return null;
    }

    _pendingGesture = candidate;
    final pendingSince = _pendingGestureSince ?? now;
    final stableReadyAt = pendingSince.add(AppConfig.gestureStabilizationDelay);
    final transitionReadyAt = lastAcceptedAt?.add(
      AppConfig.gestureTransitionDelay,
    );

    final readyAt =
        transitionReadyAt != null && transitionReadyAt.isAfter(stableReadyAt)
        ? transitionReadyAt
        : stableReadyAt;

    if (!now.isBefore(readyAt)) {
      reset();
      return candidate;
    }

    return null;
  }
}
