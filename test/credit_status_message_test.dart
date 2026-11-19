import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:bridgechat/app_language.dart';
import 'package:bridgechat/message_bubble.dart';
import 'package:bridgechat/chat_display_preferences.dart';

void main() {
  setUpAll(() async => initializeDateFormatting('ko'));
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.instance.initialize();
    await ChatDisplayPreferences.instance.initialize();
  });
  for (final item in {'no_day_pass': 'adPairNeedsPass', 'no_credit': 'creditNoBalance', 'unavailable': 'creditUnavailable'}.entries) {
    testWidgets('${item.key} explains the reason instead of indefinite pending', (t) async {
      await t.pumpWidget(LanguageScope(child: MaterialApp(home: Scaffold(body: MessageBubble(
        senderId: 'sender', currentUserId: 'recipient', originalText: 'Баярлалаа.',
        translatedText: '', sourceLang: 'mn', targetLang: 'ko',
        timestamp: DateTime(2026, 11, 19), translationStatus: item.key,
      )))));
      expect(find.textContaining(AppLanguage.instance.text(item.value), findRichText: true), findsOneWidget);
      expect(find.textContaining('Баярлалаа.', findRichText: true), findsOneWidget);
      expect(find.textContaining(AppLanguage.instance.text('translationPending'), findRichText: true), findsNothing);
    });
  }
}
