import 'dart:convert';
import 'mobile_web_navigation.dart';

const iosRewardSampleUnit = 'ca-app-pub-3940256099942544/1712485313';
const iosRewardMemberUnit = 'ca-app-pub-7142914884555224/8993940063';
const iosRewardLeaderUnit = 'ca-app-pub-7142914884555224/6918120261';

/// A server-issued session crosses the bridge; login credentials never do.
class NativeRewardRequest {
  final String id, action, uid;
  final String? sessionId, adUnitId;
  final bool testAds;
  const NativeRewardRequest._(
    this.id,
    this.action,
    this.uid,
    this.sessionId,
    this.adUnitId,
    this.testAds,
  );

  static NativeRewardRequest? parse(
    String raw,
    String nonce,
    Uri? page, {
    required bool testMode,
  }) {
    if (raw.length > 1536 ||
        nonce.length < 32 ||
        page == null ||
        !isTrustedTongyeokPage(page)) {
      return null;
    }
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic> ||
          data['nonce'] != nonce ||
          data['id'] is! String ||
          !RegExp(r'^r[1-9][0-9]{0,8}$').hasMatch(data['id']) ||
          data['uid'] is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{20,128}$').hasMatch(data['uid'])) {
        return null;
      }
      final action = data['action'];
      final keys = {'id', 'action', 'uid', 'nonce'};
      if (action == 'show') {
        keys.addAll({'sessionId', 'adUnitId', 'testAds'});
        if (data['sessionId'] is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(data['sessionId']) ||
            data['testAds'] != testMode ||
            !(testMode
                    ? {iosRewardSampleUnit}
                    : {iosRewardMemberUnit, iosRewardLeaderUnit})
                .contains(data['adUnitId'])) {
          return null;
        }
      } else if (action != 'prepare' && action != 'privacy') {
        return null;
      }
      if (data.length != keys.length || !data.keys.every(keys.contains)) {
        return null;
      }
      return NativeRewardRequest._(
        data['id'],
        action,
        data['uid'],
        data['sessionId'],
        data['adUnitId'],
        data['testAds'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}
