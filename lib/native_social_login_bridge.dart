import 'dart:convert';

import 'mobile_web_navigation.dart';

enum NativeSocialProvider { google, apple }

class NativeSocialRequest {
  const NativeSocialRequest(
    this.id,
    this.provider,
    this.legacyToken,
    this.expectedUid,
  );

  final String id;
  final NativeSocialProvider provider;
  final String? legacyToken;
  final String? expectedUid;

  static NativeSocialRequest? parse(String raw, String nonce, Uri? page) {
    if (nonce.length < 32 || page == null || !isTrustedTongyeokPage(page)) {
      return null;
    }
    if (raw.length > 8704) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic> ||
          json.length != 5 ||
          json['nonce'] != nonce ||
          !json.containsKey('legacyToken') ||
          !json.containsKey('expectedUid')) {
        return null;
      }
      final id = json['id'];
      if (id is! String || !RegExp(r'^s[1-9][0-9]{0,8}$').hasMatch(id)) {
        return null;
      }
      final provider = switch (json['provider']) {
        'google' => NativeSocialProvider.google,
        'apple' => NativeSocialProvider.apple,
        _ => null,
      };
      final legacyToken = json['legacyToken'];
      final expectedUid = json['expectedUid'];
      if (legacyToken != null &&
          (legacyToken is! String ||
              !RegExp(r'^[a-zA-Z0-9_.-]{1,8192}$').hasMatch(legacyToken))) {
        return null;
      }
      if (expectedUid != null &&
          (legacyToken != null ||
              expectedUid is! String ||
              !RegExp(r'^[A-Za-z0-9_-]{20,128}$').hasMatch(expectedUid))) {
        return null;
      }
      return provider == null
          ? null
          : NativeSocialRequest(
              id,
              provider,
              legacyToken as String?,
              expectedUid as String?,
            );
    } on FormatException {
      return null;
    }
  }
}

String nativeSocialLoginScript(String nonce) =>
    _script.replaceFirst('__NONCE__', jsonEncode(nonce));

const _script = r'''
(() => {
  if (window !== window.top || !window.TongyeokNativeSocialLogin ||
      window.__tongyeokSocialLoginComplete) return;
  const nonce = __NONCE__;
  let sequence = 0;
  let pending;
  window.__tongyeokSocialLoginComplete = (key, id, token) => {
    if (key !== nonce || pending?.id !== id) return;
    const request = pending;
    pending = undefined;
    clearTimeout(request.timeout);
    if (typeof token === 'string' && token) request.resolve(token);
    else request.reject(new Error('socialLoginError'));
  };
  window.tongyeokSocialLogin = (provider, legacyToken = null, expectedUid = null) => new Promise((resolve, reject) => {
    if (pending || !['google', 'apple'].includes(provider)) {
      reject(new Error('socialLoginError'));
      return;
    }
    const id = 's' + (++sequence);
    const timeout = setTimeout(() => {
      window.__tongyeokSocialLoginComplete(nonce, id, null);
    }, 180000);
    pending = {id, timeout, resolve, reject};
    try {
      window.TongyeokNativeSocialLogin.postMessage(JSON.stringify({id, provider, nonce, legacyToken, expectedUid}));
    } catch (_) {
      window.__tongyeokSocialLoginComplete(nonce, id, null);
    }
  });
  window.tongyeokSocialLoginAvailable = true;
})();
''';
