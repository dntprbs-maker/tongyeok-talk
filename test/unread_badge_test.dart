import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridgechat/read_receipts.dart';
import 'package:bridgechat/app_language.dart';
void main() {
  testWidgets('Unread badge is hidden at zero, counts incoming, and caps at 99+', (tester) async {
    Future<void> show(int count) async { await tester.pumpWidget(LanguageScope(child: MaterialApp(home: Scaffold(body: UnreadBadge(count:count))))); }
    await show(0); expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
    await show(2); expect(find.text('2'), findsOneWidget);
    await show(120); expect(find.text('99+'), findsOneWidget);
  });
}
