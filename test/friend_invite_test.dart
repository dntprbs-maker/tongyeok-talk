import 'package:bridgechat/app_language.dart';
import 'package:bridgechat/referral_invite.dart';
import 'package:bridgechat/referral_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

const code = 'A1B2C3D4E5F6A7B8';

Future<void> openInvite(WidgetTester tester, String language) async {
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
          body: Center(
            child: ReferralScreen(
              loadStatus:
                  () async => {
                    'code': code,
                    'waitDays': 0,
                    'pending': 2,
                    'rewarded': 1,
                  },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Mongolian sender opens a Korean QR without overflow', (
    tester,
  ) async {
    await openInvite(tester, 'mn');
    expect(find.text('Хүлээгдэж буй 2'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.qr_code));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Солонгос хэл'), findsOneWidget);
    await tester.tap(find.text('Солонгос хэл'));
    await tester.pumpAndSettle();
    expect(find.text('카메라로 QR을 찍어 주세요'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(friendReferralLink(code, 'ko').queryParameters, {
      'r': code,
      'l': 'ko',
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'contact selection fills a formatted number and SMS follows recipient language',
    (tester) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      const contacts = MethodChannel('tongyeok/contacts');
      const invite = MethodChannel('tongyeok/invite');
      Map<Object?, Object?>? draft;
      messenger.setMockMethodCallHandler(contacts, (call) async {
        expect(call.method, 'pickPhone');
        return '+82 10 0000 0001';
      });
      messenger.setMockMethodCallHandler(invite, (call) async {
        expect(call.method, 'composeSms');
        draft = call.arguments as Map<Object?, Object?>;
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(contacts, null);
        messenger.setMockMethodCallHandler(invite, null);
      });
      await openInvite(tester, 'ko');
      await tester.tap(find.byIcon(Icons.sms_outlined));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, '몽골어'), findsOneWidget);
      await tester.tap(find.text('몽골어'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('연락처에서 찾기'));
      await tester.pumpAndSettle();
      expect(find.text('010-0000-0001'), findsWidgets);
      await tester.enterText(find.byType(TextField), '01000000001');
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '010-0000-0001',
      );
      await tester.ensureVisible(find.text('초대하기'));
      await tester.tap(find.text('초대하기'));
      await tester.pumpAndSettle();
      expect(draft?['phone'], '01000000001');
      final body = draft?['body'] as String;
      expect(body, startsWith('Орчуулагч Ток-д урьж байна!'));
      expect(body, contains('l=mn&p=a'));
      expect(body, contains('l=mn&p=i'));
      expect(tester.takeException(), isNull);
    },
  );

  test('legacy SMS remains available next to separate Korean store links', () {
    expect(referralMessage(code), contains('/rewardApi/invite?ref='));
    final lines = referralMessage(code, language: 'ko').split('\n');
    expect(lines[0], '통역톡에 초대합니다!');
    expect(Uri.parse(lines[4]).queryParameters['p'], 'a');
    expect(Uri.parse(lines[7]).queryParameters['p'], 'i');
  });
}
