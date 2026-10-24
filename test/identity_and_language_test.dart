import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bridgechat/phone_identity.dart';
import 'package:bridgechat/app_language.dart';
import 'package:bridgechat/main.dart';

void main() {
  test('Korean local and international formats resolve to one login', () {
    final a = PhoneIdentity.parse('010-1234-5678'),
        b = PhoneIdentity.parse('+82 (0)10 1234 5678');
    expect(a.e164, '+821012345678');
    expect(a.authAlias, b.authAlias);
    expect(PhoneIdentity.parse('00821012345678').authAlias, a.authAlias);
  });
  test('Mongolian and Korean numbers stay distinct', () {
    final mn = PhoneIdentity.parse('9911-2233', defaultCountry: '976');
    expect(mn.e164, '+97699112233');
    expect(mn.directoryKey, '97699112233');
    expect(mn.authAlias, PhoneIdentity.parse('+976 9911 2233').authAlias);
    expect(mn.authAlias, isNot(PhoneIdentity.parse('01099112233').authAlias));
  });
  test('Malformed and unsupported numbers cannot become login IDs', () {
    for (final value in [
      '',
      '010abc12345678',
      '+1 202 555 0100',
      '123',
      '+820',
    ]) {
      expect(() => PhoneIdentity.parse(value), throwsFormatException);
    }
  });
  test('Korea-only entry accepts local and international Korean numbers', () {
    expect(PhoneIdentity.parseKorean('010-1234-5678').e164, '+821012345678');
    expect(PhoneIdentity.parseKorean('+82 10 1234 5678').e164, '+821012345678');
    expect(
      () => PhoneIdentity.parseKorean('+97699112233'),
      throwsFormatException,
    );
    expect(() => PhoneIdentity.parseKorean('99112233'), throwsFormatException);
  });
  test('Every UI key has both Korean and Mongolian text', () {
    for (final entry in messages.entries) {
      expect(entry.value.length, 2, reason: entry.key);
      expect(
        entry.value.every((v) => v.trim().isNotEmpty),
        isTrue,
        reason: entry.key,
      );
    }
  });
  testWidgets('Korean defaults, Mongolian signup and choice survives reload', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.instance.initialize();
    expect(AppLanguage.instance.code, 'ko');
    await tester.pumpWidget(const MyApp(isLoggedIn: false));
    await tester.pumpAndSettle();
    expect(find.text('통역톡'), findsOneWidget);
    expect(find.text('회원가입'), findsOneWidget);
    await tester.tap(find.text('Монгол'));
    await tester.pumpAndSettle();
    expect(find.text('Орчуулагч Ток'), findsOneWidget);
    await tester.ensureVisible(find.text('Бүртгүүлэх'));
    await tester.tap(find.text('Бүртгүүлэх'));
    await tester.pumpAndSettle();
    expect(find.text('Нэр'), findsOneWidget);
    expect(find.text('Утасны дугаар'), findsOneWidget);
    expect(find.text('Нууц үг'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('auth-phone')),
      '010-1234-5678',
    );
    expect(tester.widget<TextFormField>(find.byKey(const ValueKey('auth-phone'))).controller!.text, '010-1234-5678');
    expect(find.text('Email'), findsNothing);
    expect(find.text('Username'), findsNothing);
    await AppLanguage.instance.initialize();
    expect(AppLanguage.instance.code, 'mn');
    await tester.tap(find.text('한국어'));
    await tester.pumpAndSettle();
    expect(find.text('이름'), findsOneWidget);
    expect(find.text('전화번호'), findsOneWidget);
    expect(find.text('비밀번호'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
