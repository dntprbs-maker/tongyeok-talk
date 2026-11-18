import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridgechat/app_language.dart';
import 'package:bridgechat/reward_ads_section.dart';

void main() {
  Widget panel({
    String role = 'member',
    bool busy = false,
    bool supported = true,
    int progress = 0,
    required VoidCallback onWatch,
  }) => LanguageScope(
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: RewardAdsPanel(
            role: role,
            availableCredits: 99,
            busy: busy,
            supported: supported,
            leaderAdProgress: progress,
            testMode: false,
            onWatch: onWatch,
            onPrivacy: () {},
          ),
        ),
      ),
    ),
  );
  testWidgets(
    'member keeps 50-credit offer and prevents repeated taps while loading',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(panel(onWatch: () => calls++));
      expect(find.textContaining('50문장을 번역'), findsOneWidget);
      await tester.tap(find.text('광고 보고 50문장 충전'));
      expect(calls, 1);
      await tester.pumpWidget(panel(busy: true, onWatch: () => calls++));
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '광고 준비 중…'))
            .onPressed,
        isNull,
      );
      expect(calls, 1);
    },
  );
  testWidgets('leader preserves two-ad progress and requires the second ad', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      panel(role: 'leader', progress: 1, onWatch: () => calls++),
    );
    expect(find.textContaining('광고 2편'), findsOneWidget);
    expect(find.text('두 번째 광고 보기 (1/2)'), findsOneWidget);
    await tester.tap(find.text('두 번째 광고 보기 (1/2)'));
    expect(calls, 1);
  });
  testWidgets('unsupported browsers cannot start an ad', (tester) async {
    await tester.pumpWidget(
      panel(supported: false, onWatch: () => fail('unsupported ad started')),
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, '광고 보고 50문장 충전'),
          )
          .onPressed,
      isNull,
    );
    expect(find.textContaining('광고를 지원하는 설치형 앱'), findsOneWidget);
  });
  test(
    'expiry displays the final usable Korean minute and reward text has both languages',
    () {
      final last = lastPassMinute(DateTime.utc(2026, 11, 20, 15))!;
      expect([last.month, last.day, last.hour, last.minute], [11, 20, 23, 59]);
      for (final entry in messages.entries.where(
        (e) => e.key.startsWith('ad'),
      )) {
        expect(entry.value.length, 2);
        expect(entry.value.every((text) => text.trim().isNotEmpty), isTrue);
      }
    },
  );
}
