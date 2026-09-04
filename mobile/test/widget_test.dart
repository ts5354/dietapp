import 'package:dietapp/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the placeholder home screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: DietApp()));

    expect(find.text('dietapp'), findsOneWidget);
    expect(find.text('Health logging is ready to begin.'), findsOneWidget);
  });
}
