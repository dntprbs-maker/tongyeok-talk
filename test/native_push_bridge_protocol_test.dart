import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridgechat/native_push_bridge_protocol.dart';

void main() {
  const nonce = 'verified_page_nonce_1234567890123456789012345';
  const uid = 'QA_user_12345678901234567890';
  final page = Uri.parse('https://dntprbs-maker.github.io/tongyeok-talk/');
  String request({
    String key = nonce,
    String action = 'state',
    String user = uid,
  }) => jsonEncode({'id': 'p1', 'nonce': key, 'action': action, 'uid': user});
  test('known operations from the trusted page are accepted', () {
    for (final action in ['state', 'enable', 'disable']) {
      expect(
        NativePushRequest.parse(request(action: action), nonce, page)?.action,
        action,
      );
    }
  });
  test(
    'foreign pages, missing page and forged nonce cannot call native push',
    () {
      for (final uri in [
        null,
        Uri.parse('https://evil.invalid/'),
        Uri.parse('https://dntprbs-maker.github.io/other/'),
        Uri.parse('https://dntprbs-maker.github.io/tongyeok-talk-evil/'),
      ]) {
        expect(NativePushRequest.parse(request(), nonce, uri), isNull);
      }
      expect(
        NativePushRequest.parse(request(key: 'forged'), nonce, page),
        isNull,
      );
    },
  );
  test(
    'invalid identities, oversized input and unsupported actions fail closed',
    () {
      for (final raw in [
        '[]',
        '{',
        'x' * 1025,
        request(user: '../other-user'),
        request(action: 'openUrl'),
        request().replaceFirst('"p1"', '"p0"'),
        request().replaceFirst('{', '{"extra":true,'),
      ]) {
        expect(
          NativePushRequest.parse(raw, nonce, page),
          isNull,
          reason: raw.substring(0, raw.length.clamp(0, 50)),
        );
      }
    },
  );
}
