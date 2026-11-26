import 'dart:convert';

import 'package:bridgechat/native_referral_sms.dart';
import 'package:bridgechat/referral_invite.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final nonce = 'a' * 43;
  final page = Uri.https('tongyeok-talk-lab-20261024.web.app', '/mobile/');
  const code = '0123456789ABCDEF';
  final request = {
    'id': 1,
    'nonce': nonce,
    'phone': '+821012345678',
    'code': code,
  };

  test('valid SMS request generates the existing referral link', () {
    final parsed = NativeReferralSmsRequest.parse(
      jsonEncode(request),
      nonce,
      page,
    );
    expect(parsed?.phone, '+821012345678');
    final link = Uri.parse(referralMessage(parsed!.code).split('\n').last);
    expect(link.host, referralEndpoint.host);
    expect(link.path, '/rewardApi/invite');
    expect(link.queryParameters, {'ref': code});
  });

  test('SMS request requires its own app page and the current page nonce', () {
    final raw = jsonEncode(request);
    expect(NativeReferralSmsRequest.parse(raw, 'b' * 43, page), isNull);
    expect(
      NativeReferralSmsRequest.parse(raw, nonce, page.replace(path: '/')),
      isNull,
    );
    expect(
      NativeReferralSmsRequest.parse(
        raw,
        nonce,
        page.replace(host: 'example.com'),
      ),
      isNull,
    );
  });

  test('SMS request rejects invalid recipients and arbitrary message text', () {
    for (final fields in [
      {'phone': '+821012345678,012345678'},
      {'phone': '01012345678?body=other'},
      {'code': 'wrong'},
      {'body': 'unexpected message'},
    ]) {
      expect(
        NativeReferralSmsRequest.parse(
          jsonEncode({...request, ...fields}),
          nonce,
          page,
        ),
        isNull,
      );
    }
  });
}
