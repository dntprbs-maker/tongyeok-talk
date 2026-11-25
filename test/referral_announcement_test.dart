import 'package:bridgechat/app_language.dart';
import 'package:bridgechat/referral_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final language in ['ko', 'mn']) {
    testWidgets('the $language referral dialog uses the selected language', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'tongyeok.language': language});
      await AppLanguage.instance.initialize();
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        LanguageScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder:
                    (context) => TextButton(
                      onPressed:
                          () => showReferralAnnouncement(context, language),
                      child: const Icon(Icons.card_giftcard),
                    ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.card_giftcard));
      await tester.pumpAndSettle();
      final popup = find.byType(Dialog);
      expect(popup, findsOneWidget);
      final poster = find.descendant(of: popup, matching: find.byType(Image));
      if (language == 'ko') {
        expect(poster, findsOneWidget);
        expect(find.text('문자로 초대하기'), findsOneWidget);
      } else {
        expect(poster, findsNothing);
        expect(find.text('Найзаа уриад урамшуулал аваарай'), findsOneWidget);
        expect(find.text('5 өдрийн ашиглах эрх'), findsOneWidget);
        expect(find.text('500 өгүүлбэр орчуулах эрх'), findsOneWidget);
        expect(find.textContaining('30 хоног'), findsOneWidget);
        expect(find.textContaining('10 өөр өдөр'), findsOneWidget);
        expect(find.text('Мессежээр урих'), findsOneWidget);
        final visibleStrings = tester.widgetList<Text>(
          find.descendant(of: popup, matching: find.byType(Text)),
        );
        expect(
          visibleStrings.any(
            (text) => RegExp(r'[가-힣]').hasMatch(text.data ?? ''),
          ),
          isFalse,
        );
      }
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(popup, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
