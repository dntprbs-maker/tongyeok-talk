import 'dart:convert';

import 'mobile_web_navigation.dart';
import 'referral_invite.dart';

bool isReferralSmsPage(Uri? page) =>
    page != null &&
    isTrustedTongyeokPage(page) &&
    (page.host == 'tongyeok-talk-lab-20261024.web.app' || socialLocalPreview);

class NativeReferralSmsRequest {
  const NativeReferralSmsRequest(this.id, this.phone, this.code);

  final int id;
  final String phone;
  final String code;

  static NativeReferralSmsRequest? parse(String raw, String nonce, Uri? page) {
    if (raw.length > 256 || nonce.length < 32 || !isReferralSmsPage(page)) {
      return null;
    }
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic> ||
          data.length != 4 ||
          data['nonce'] != nonce) {
        return null;
      }
      final id = data['id'];
      final phone = data['phone'];
      final code = data['code'];
      if (id is! int ||
          id < 1 ||
          id > 999999999 ||
          phone is! String ||
          !isReferralPhone(phone) ||
          code is! String ||
          !isReferralCode(code)) {
        return null;
      }
      return NativeReferralSmsRequest(id, phone, code);
    } on FormatException {
      return null;
    }
  }
}

String nativeReferralSmsScript(String nonce) =>
    _script.replaceFirst('__NONCE__', jsonEncode(nonce));

const _script = r'''
(() => {
  if (window !== window.top || !window.TongyeokNativeReferralSms ||
      window.tongyeokComposeReferralSms) return;
  const nonce = __NONCE__;
  let sequence = 0;
  let pending;
  window.__tongyeokReferralSmsResult = (key, id, opened) => {
    if (key !== nonce || pending?.id !== id) return;
    const request = pending;
    pending = undefined;
    clearTimeout(request.timeout);
    request.resolve(opened === true);
  };
  window.tongyeokComposeReferralSms = (phone, code) => new Promise((resolve) => {
    if (pending) {
      resolve(false);
      return;
    }
    const id = ++sequence;
    const fail = () => window.__tongyeokReferralSmsResult(nonce, id, false);
    pending = {id, resolve, timeout: setTimeout(fail, 10000)};
    try {
      window.TongyeokNativeReferralSms.postMessage(JSON.stringify({nonce, id, phone, code}));
    } catch (_) {
      fail();
    }
  });
})();
''';
