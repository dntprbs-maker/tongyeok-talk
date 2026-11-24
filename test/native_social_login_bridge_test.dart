import 'dart:convert';

import 'package:bridgechat/native_social_login_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final trusted = Uri.parse('https://dntprbs-maker.github.io/tongyeok-talk/');
  const nonce = 'a-page-bound-secret-of-at-least-32-characters';
  String message([Map<String, Object?> overrides = const {}]) => jsonEncode({
    'id': 's1',
    'provider': 'apple',
    'nonce': nonce,
    'legacyToken': null,
    'expectedUid': null,
    ...overrides,
  });

  test('accepts only the supported provider from the current app page', () {
    expect(
      NativeSocialRequest.parse(message(), nonce, trusted)?.provider,
      NativeSocialProvider.apple,
    );
    expect(NativeSocialRequest.parse(message(), 'wrong', trusted), isNull);
    expect(
      NativeSocialRequest.parse(message(), nonce, Uri.https('example.com')),
      isNull,
    );
    expect(
      NativeSocialRequest.parse(
        message({'provider': 'password'}),
        nonce,
        trusted,
      ),
      isNull,
    );
  });

  test('keeps account linking and reauthentication mutually exclusive', () {
    const account = 'existingAuthenticatedAccount';
    expect(
      NativeSocialRequest.parse(
        message({'expectedUid': account}),
        nonce,
        trusted,
      )?.expectedUid,
      account,
    );
    expect(
      NativeSocialRequest.parse(
        message({'expectedUid': account, 'legacyToken': 'hello.token'}),
        nonce,
        trusted,
      ),
      isNull,
    );
  });
}
