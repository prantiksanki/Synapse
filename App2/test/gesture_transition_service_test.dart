import 'package:flutter_test/flutter_test.dart';
import 'package:synapse/models/gesture_result.dart';
import 'package:synapse/services/gesture_transition_service.dart';

void main() {
  GestureResult gesture(String label, DateTime at) => GestureResult(
    label: label,
    labelIndex: 0,
    confidence: 0.95,
    probabilities: {label: 0.95},
    timestampMs: at.millisecondsSinceEpoch,
  );

  test('waits one second before accepting a different symbol', () {
    final service = GestureTransitionService();
    final acceptedAt = DateTime(2026, 1, 1, 12, 0, 0);

    expect(
      service.acceptStableGesture(
        candidate: gesture(
          'B',
          acceptedAt.add(const Duration(milliseconds: 200)),
        ),
        currentLabel: 'A',
        now: acceptedAt.add(const Duration(milliseconds: 200)),
        lastAcceptedAt: acceptedAt,
      ),
      isNull,
    );

    expect(
      service.acceptStableGesture(
        candidate: gesture(
          'B',
          acceptedAt.add(const Duration(milliseconds: 700)),
        ),
        currentLabel: 'A',
        now: acceptedAt.add(const Duration(milliseconds: 700)),
        lastAcceptedAt: acceptedAt,
      ),
      isNull,
    );

    final accepted = service.acceptStableGesture(
      candidate: gesture('B', acceptedAt.add(const Duration(seconds: 1))),
      currentLabel: 'A',
      now: acceptedAt.add(const Duration(seconds: 1)),
      lastAcceptedAt: acceptedAt,
    );

    expect(accepted?.label, 'B');
  });

  test('resets pending transition when the candidate label changes', () {
    final service = GestureTransitionService();
    final acceptedAt = DateTime(2026, 1, 1, 12, 0, 0);

    expect(
      service.acceptStableGesture(
        candidate: gesture(
          'C',
          acceptedAt.add(const Duration(milliseconds: 300)),
        ),
        currentLabel: 'A',
        now: acceptedAt.add(const Duration(milliseconds: 300)),
        lastAcceptedAt: acceptedAt,
      ),
      isNull,
    );

    expect(
      service.acceptStableGesture(
        candidate: gesture(
          'B',
          acceptedAt.add(const Duration(milliseconds: 800)),
        ),
        currentLabel: 'A',
        now: acceptedAt.add(const Duration(milliseconds: 800)),
        lastAcceptedAt: acceptedAt,
      ),
      isNull,
    );

    expect(
      service.acceptStableGesture(
        candidate: gesture(
          'B',
          acceptedAt.add(const Duration(milliseconds: 1200)),
        ),
        currentLabel: 'A',
        now: acceptedAt.add(const Duration(milliseconds: 1200)),
        lastAcceptedAt: acceptedAt,
      ),
      isNull,
    );

    final accepted = service.acceptStableGesture(
      candidate: gesture(
        'B',
        acceptedAt.add(const Duration(milliseconds: 1300)),
      ),
      currentLabel: 'A',
      now: acceptedAt.add(const Duration(milliseconds: 1300)),
      lastAcceptedAt: acceptedAt,
    );

    expect(accepted?.label, 'B');
  });
}
