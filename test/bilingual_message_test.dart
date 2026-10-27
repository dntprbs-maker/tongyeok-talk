import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bridgechat/app_language.dart';
import 'package:bridgechat/message_bubble.dart';
import 'package:bridgechat/chat_display_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ko');
    await initializeDateFormatting('mn');
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.instance.initialize();
    await ChatDisplayPreferences.instance.initialize();
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
          t.getTopLeft(find.textContaining('청소해 주세요', findRichText: true)).dy,
          lessThan(
            t
                .getTopLeft(
                  find.textContaining('Цэвэрлээрэй', findRichText: true),
                )
                .dy,
          ),
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
      t.getTopLeft(find.textContaining('Цэвэрлээрэй', findRichText: true)).dy,
      lessThan(
        t.getTopLeft(find.textContaining('청소해 주세요', findRichText: true)).dy,
      ),
    );
  });
  testWidgets('failed translation retains original and invokes retry', (
    t,
  ) async {
    var calls = 0;
    await t.pumpWidget(bubble(status: 'failed', retry: () => calls++));
    await t.pumpAndSettle();
    expect(find.textContaining('청소해 주세요', findRichText: true), findsOneWidget);
    await t.tap(find.text('번역 다시 시도'));
    expect(calls, 1);
  });

  testWidgets(
    'hidden other language reveals original or translation for each source',
    (t) async {
      await ChatDisplayPreferences.instance.setShowOtherLanguage(false);
      for (final source in ['ko', 'mn']) {
        await t.pumpWidget(bubble(source: source));
        await t.pumpAndSettle();
        expect(
          find.textContaining('청소해 주세요', findRichText: true),
          findsOneWidget,
        );
        expect(
          find.textContaining('Цэвэрлээрэй', findRichText: true),
          findsNothing,
        );
        await t.tap(find.text(source == 'ko' ? '번역 보기' : '원문 보기'));
        await t.pump();
        expect(
          find.textContaining('Цэвэрлээрэй', findRichText: true),
          findsOneWidget,
        );
        await t.tap(find.text('접기'));
        await t.pump();
        expect(
          find.textContaining('Цэвэрлээрэй', findRichText: true),
          findsNothing,
        );
      }
    },
  );

  testWidgets(
    'hidden mode keeps foreign original during pending or failed translation',
    (t) async {
      await ChatDisplayPreferences.instance.setShowOtherLanguage(false);
      for (final status in ['pending', 'failed']) {
        await t.pumpWidget(bubble(source: 'mn', status: status));
        await t.pumpAndSettle();
        expect(
          find.textContaining('Цэвэрлээрэй', findRichText: true),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            status == 'pending' ? '번역 중이에요' : '번역하지 못했어요',
            findRichText: true,
          ),
          findsOneWidget,
        );
      }
    },
  );

  testWidgets(
    'display switch persists and updates existing bubbles without a translation request',
    (t) async {
      await t.pumpWidget(
        LanguageScope(
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  const ChatDisplaySettings(),
                  MessageBubble(
                    senderId: 'a',
                    currentUserId: 'b',
                    originalText: '청소해 주세요',
                    translatedText: 'Цэвэрлээрэй',
                    sourceLang: 'ko',
                    targetLang: 'mn',
                    timestamp: DateTime(2026),
                    translationStatus: 'done',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(
        find.textContaining('Цэвэрлээрэй', findRichText: true),
        findsOneWidget,
      );
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      expect(
        find.textContaining('Цэвэрлээрэй', findRichText: true),
        findsNothing,
      );
      await ChatDisplayPreferences.instance.initialize();
      expect(ChatDisplayPreferences.instance.showOtherLanguage, false);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          ChatDisplayPreferences.storageKey,
        ),
        false,
      );
    },
  );

  testWidgets(
    'long bilingual messages fit narrow screen and large text without overflow',
    (t) async {
      await t.binding.setSurfaceSize(const Size(320, 740));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        LanguageScope(
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 740),
                textScaler: TextScaler.linear(1.5),
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: MessageBubble(
                    senderId: 'other',
                    currentUserId: 'me',
                    originalText: List.filled(20, '청소를 완료했어요.').join(' '),
                    translatedText: List.filled(
                      20,
                      'Цэвэрлэгээ дууслаа.',
                    ).join(' '),
                    sourceLang: 'ko',
                    targetLang: 'mn',
                    timestamp: DateTime(2026),
                    translationStatus: 'done',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(t.takeException(), isNull);
      final surface = find.byKey(const ValueKey('message-surface'));
      expect(t.getSize(surface).width, lessThanOrEqualTo(320));
      expect(
        find.descendant(of: surface, matching: find.textContaining('00:00')),
        findsNothing,
      );
    },
  );
}
