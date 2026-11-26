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
    expect(find.text(language.text('interfaceLanguage')), findsNothing);
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

  testWidgets('allowed account switches the settings labels only', (
    tester,
  ) async {
    final language = AppLanguage.instance;
    addTearDown(() => language.keepAccountLanguageFor(null));
    language.useAccountLanguage('mado', 'mn');
    await tester.pumpWidget(
      LanguageScope(child: const MaterialApp(home: SettingsScreen())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Дэлгэцийн хэл'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('한국어'));
    await tester.pumpAndSettle();
    expect(find.text('화면 언어'), findsOneWidget);
    expect(language.profileLanguage, 'Mongolian');
  });
}
