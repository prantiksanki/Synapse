import 'package:flutter_test/flutter_test.dart';
import 'package:synapse/main.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const SignLanguageApp());
    expect(find.text('SYNAPSE'), findsWidgets);
  });
}
