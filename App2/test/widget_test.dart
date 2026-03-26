import 'package:flutter_test/flutter_test.dart';
import 'package:synapse/main.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const SignLanguageApp(
      onboardingDone: true,
      role: 'deaf',
      modelsReady: true,
    ));
    expect(find.text('SYNAPSE'), findsWidgets);
  });
}
