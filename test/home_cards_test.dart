import 'package:bridgechat/app_language.dart';
import 'package:bridgechat/read_receipts.dart';
import 'package:bridgechat/translation_wallet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget wrapKorean(Widget child) {
  return LanguageScope(
    child: MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 180, child: child)),
      ),
    ),
  );
}

void main() {
  final now = DateTime.utc(2026, 11, 27, 15, 30);
  final expiry = DateTime.utc(2027, 11, 27, 15, 0);

  group('remainingPassDays', () {
    test('counts inclusive 365 days', () {
      expect(remainingPassDays(expiry, now), 365);
    });

    test('keeps the day count just before KST midnight', () {
      final justBefore = DateTime.utc(2026, 11, 27, 14, 59, 59);
      expect(justBefore.add(const Duration(hours: 9)).day, 27);
      expect(remainingPassDays(expiry, justBefore), 366);
    });

    test('keeps the day count exactly at KST midnight', () {
      final kstMidnight = DateTime.utc(2026, 11, 27, 15, 0);
      expect(kstMidnight.add(const Duration(hours: 9)).day, 28);
      expect(remainingPassDays(expiry, kstMidnight), 365);
    });

    test('returns 0 for a null expiry', () {
      expect(remainingPassDays(null, now), 0);
    });

    test('returns 0 for an expired pass', () {
      expect(remainingPassDays(now, now), 0);
      expect(
        remainingPassDays(now.subtract(const Duration(seconds: 1)), now),
        0,
      );
      expect(remainingPassDays(now.subtract(const Duration(days: 1)), now), 0);
    });

    test('returns 1 for a pass active for one day', () {
      expect(remainingPassDays(now.add(const Duration(hours: 12)), now), 1);
    });
  });

  group('HomePassSummary', () {
    testWidgets(
      'shows the same pass in Mongolian when only display language changes',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final language = AppLanguage.instance;
        language.useAccountLanguage('preview-account', 'ko');
        await language.selectDisplayLanguage('preview-account', 'mn');
        addTearDown(() => language.keepAccountLanguageFor(null));
        await tester.pumpWidget(
          wrapKorean(HomePassSummary(expiry: expiry, now: now)),
        );
        expect(find.textContaining('365 өдөр'), findsOneWidget);
        expect(find.textContaining('2027 оны 11-р сарын 27'), findsOneWidget);
        expect(language.code, 'ko');
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets('shows Korean label, remaining days and expiry date at 180px', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapKorean(HomePassSummary(expiry: expiry, now: now)),
      );
      await tester.pump();

      expect(find.textContaining('이용 기간'), findsWidgets);
      expect(find.textContaining('365일 남음'), findsWidgets);
      expect(find.textContaining('2027년 11월 27일까지'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows today label when the pass ends today', (tester) async {
      final todayExpiry = DateTime.utc(2026, 11, 27, 20, 0);
      await tester.pumpWidget(
        wrapKorean(HomePassSummary(expiry: todayExpiry, now: now)),
      );
      await tester.pump();

      expect(find.textContaining('이용 기간'), findsWidgets);
      expect(find.textContaining('오늘까지'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows no pass message without a stale date', (tester) async {
      await tester.pumpWidget(
        wrapKorean(HomePassSummary(expiry: null, now: now)),
      );
      await tester.pump();

      expect(find.textContaining('이용권 없음'), findsWidgets);
      expect(find.textContaining('년'), findsNothing);
      expect(find.textContaining('까지'), findsNothing);
      expect(find.textContaining('남음'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('UnreadBadge', () {
    testWidgets('caps at 99+ without avatar or initial', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UnreadBadge(count: 120, bubbleIcon: true, displayName: '바보'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('99+'), findsOneWidget);
      expect(find.byType(CircleAvatar), findsNothing);
      expect(find.text('바'), findsNothing);
      expect(find.text('바보'), findsNothing);
    });
  });
}
