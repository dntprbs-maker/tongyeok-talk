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
      expect(poster, findsOneWidget);
      final image = tester.widget<Image>(poster);
      expect(
        (image.image as AssetImage).assetName,
        language == 'mn'
            ? 'assets/images/referral-announcement-mn.png'
            : 'assets/images/referral-announcement.png',
      );
      expect(image.semanticLabel, contains('30'));
      expect(image.semanticLabel, contains('500'));
      expect(
        find.text(language == 'mn' ? 'Мессежээр урих' : '문자로 초대하기'),
        findsOneWidget,
      );
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(popup, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
