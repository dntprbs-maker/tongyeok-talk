import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridgechat/native_reward_bridge_protocol.dart';

void main() {
  const nonce = 'verified_reward_nonce_123456789012345678901234';
  const uid = 'QA_user_12345678901234567890';
  final page = Uri.parse('https://dntprbs-maker.github.io/tongyeok-talk/');
  Map<String, dynamic> request(String action) => {
    'id': 'r1',
    'nonce': nonce,
    'uid': uid,
    'action': action,
    if (action == 'show') ...{
      'sessionId': 'a' * 64,
      'adUnitId': iosRewardSampleUnit,
      'testAds': true,
    },
  };
  NativeRewardRequest? parse(
    Map<String, dynamic> data, {
    bool testMode = true,
    Uri? uri,
  }) => NativeRewardRequest.parse(
    jsonEncode(data),
    nonce,
    uri ?? page,
    testMode: testMode,
  );
  test('only prepare, privacy and a pinned iOS show request are accepted', () {
    for (final action in ['prepare', 'privacy', 'show']) {
      expect(parse(request(action))?.action, action);
    }
    for (final unit in [iosRewardMemberUnit, iosRewardLeaderUnit]) {
      final data =
          request('show')
            ..['testAds'] = false
            ..['adUnitId'] = unit;
      expect(parse(data, testMode: false)?.adUnitId, unit);
    }
  });
  test('foreign pages and a forged page nonce cannot access native ads', () {
    for (final uri in [
      Uri.parse('https://evil.invalid/'),
      Uri.parse('https://dntprbs-maker.github.io/other/'),
      Uri.parse('http://dntprbs-maker.github.io/tongyeok-talk/'),
    ]) {
      expect(parse(request('prepare'), uri: uri), isNull);
    }
    expect(parse(request('prepare')..['nonce'] = 'forged'), isNull);
    expect(
      NativeRewardRequest.parse(
        jsonEncode(request('prepare')),
        nonce,
        null,
        testMode: true,
      ),
      isNull,
    );
  });
  test(
    'Android units, unpinned units and test/real mode substitutions fail closed',
    () {
      for (final unit in [
        'ca-app-pub-3940256099942544/5224354917',
        'ca-app-pub-7142914884555224/6464698858',
        'ca-app-pub-9999999999999999/9999999999',
      ]) {
        expect(parse(request('show')..['adUnitId'] = unit), isNull);
      }
      expect(parse(request('show'), testMode: false), isNull);
      expect(
        parse(
          request('show')
            ..['testAds'] = false
            ..['adUnitId'] = iosRewardMemberUnit,
        ),
        isNull,
      );
    },
  );
  test(
    'malformed sessions, credentials, extra fields and unsupported actions are rejected',
    () {
      for (final data in [
        request('show')..['sessionId'] = 'not-a-session',
        request('show')..['testAds'] = 'true',
        request('prepare')..['idToken'] = 'must-not-cross-the-bridge',
        request('prepare')..['uid'] = '../another-user',
        request('prepare')..['id'] = 'r0',
        request('execute'),
      ]) {
        expect(parse(data), isNull);
      }
      for (final raw in ['[]', '{', 'x' * 1537]) {
        expect(
          NativeRewardRequest.parse(raw, nonce, page, testMode: true),
          isNull,
        );
      }
    },
  );
}
