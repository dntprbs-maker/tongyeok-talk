import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/app_language.dart';
import '../lib/settings_screen.dart';

void main() {
  testWidgets('settings shows headings and opens the selected preference', (
    tester,
  ) async {
    await tester.pumpWidget(
      LanguageScope(child: const MaterialApp(home: SettingsScreen())),
    );
    await tester.pumpAndSettle();
    final language = AppLanguage.instance;
    expect(find.text(language.text('account')), findsOneWidget);
    expect(find.text(language.text('friendInvite')), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);

    await tester.tap(find.text(language.text('messageDisplay')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(language.text('showOtherLanguage')), findsOneWidget);

    await tester.tap(find.text(language.text('chatCreditClose')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
  });
}
