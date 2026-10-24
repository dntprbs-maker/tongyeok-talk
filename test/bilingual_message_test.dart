import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bridgechat/app_language.dart';
import 'package:bridgechat/message_bubble.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async { await initializeDateFormatting('ko'); await initializeDateFormatting('mn'); });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.instance.initialize();
  });
  Widget bubble({
    String status = 'done',
    String source = 'ko',
    VoidCallback? retry,
  }) => LanguageScope(
    child: MaterialApp(
      home: Scaffold(
        body: MessageBubble(
          senderId: 'a',
          currentUserId: 'a',
          originalText: source == 'ko' ? '청소해 주세요' : 'Цэвэрлээрэй',
          translatedText: source == 'ko' ? 'Цэвэрлээрэй' : '청소해 주세요',
          sourceLang: source,
          targetLang: source == 'ko' ? 'mn' : 'ko',
          timestamp: DateTime(2026, 10, 25),
          translationStatus: status,
          onRetry: retry,
        ),
      ),
    ),
  );
  testWidgets(
    'Korean preference shows Korean first for both source directions',
    (t) async {
      for (final source in ['ko', 'mn']) {
        await t.pumpWidget(bubble(source: source));
        await t.pumpAndSettle();
        expect(
          t.getTopLeft(find.text('청소해 주세요')).dy,
          lessThan(t.getTopLeft(find.text('Цэвэрлээрэй')).dy),
        );
      }
    },
  );
  testWidgets('Mongolian preference puts Mongolian first and shows both', (
    t,
  ) async {
    await AppLanguage.instance.select('mn');
    await t.pumpWidget(bubble());
    await t.pumpAndSettle();
    expect(
      t.getTopLeft(find.text('Цэвэрлээрэй')).dy,
      lessThan(t.getTopLeft(find.text('청소해 주세요')).dy),
    );
  });
  testWidgets('failed translation retains original and invokes retry', (
    t,
  ) async {
    var calls = 0;
    await t.pumpWidget(bubble(status: 'failed', retry: () => calls++));
    await t.pumpAndSettle();
    expect(find.text('청소해 주세요'), findsOneWidget);
    await t.tap(find.text('번역 다시 시도'));
    expect(calls, 1);
  });
}
