import 'package:bridgechat/app_language.dart';
import 'package:bridgechat/referral_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const rules = {
    'ko': {
      'both': '두 분 모두',
      'ten': '10',
      'five': '5일',
      'credits': '500문장',
      'button': '문자로 초대하기',
    },
    'mn': {
      'both': 'хоёулаа',
      'ten': '10 өөр өдөр',
      'five': '5 хоног',
      'credits': '500 өгүүлбэр',
      'button': 'Мессежээр урих',
    },
  };
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
      expect(poster, findsOneWidget);
      final image = tester.widget<Image>(poster);
      expect(
        (image.image as AssetImage).assetName,
        language == 'mn'
            ? 'assets/images/referral-announcement-mn.png'
            : 'assets/images/referral-announcement.png',
      );
      final label = image.semanticLabel!;
      final expected = rules[language]!;
      expect(label, contains(expected['both']));
      expect(label, contains(expected['ten']));
      expect(label, contains(expected['five']));
      expect(label, contains(expected['credits']));
      expect(label, isNot(contains('30')));
      expect(find.text(expected['button']!), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(popup, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}