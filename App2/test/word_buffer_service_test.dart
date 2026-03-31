import 'package:flutter_test/flutter_test.dart';
import 'package:synapse/models/gesture_result.dart';
import 'package:synapse/services/word_buffer.dart';

void main() {
  test('suppresses immediate duplicates and tracks active phrase', () async {
    final service = WordBufferService();
    final gesture = GestureResult(
      label: 'Open',
      labelIndex: 0,
      confidence: 0.9,
      probabilities: const {'Open': 0.9},
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );

    expect(service.ingest(gesture), isNull);
    expect(service.state.activePhrase, 'Open');

    expect(service.ingest(gesture), isNull);
    expect(service.state.activePhrase, 'Open');
  });
}
