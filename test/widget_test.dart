import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_hive/main.dart';

void main() {
  testWidgets('App loads', (WidgetTester tester) async {
    await tester.pumpWidget(const HermesHiveApp());
    expect(find.text('Hermes Hive'), findsOneWidget);
  });
}
