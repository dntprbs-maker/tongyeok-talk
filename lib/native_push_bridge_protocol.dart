import 'dart:convert';
import 'mobile_web_navigation.dart';

/// Requests are accepted only from the current, trusted top-level app page.
/// The per-page nonce is held in a JavaScript closure, not sent to subframes.
class NativePushRequest {
  final String id, action, uid;
  const NativePushRequest(this.id, this.action, this.uid);

  static NativePushRequest? parse(String raw, String nonce, Uri? page) {
    if (page == null || !isTrustedTongyeokPage(page) || raw.length > 1024) {
      return null;
    }
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic> ||
          data.length != 4 ||
          data['nonce'] != nonce ||
          nonce.length < 32 ||
          data['id'] is! String ||
          !RegExp(r'^p[1-9][0-9]{0,8}$').hasMatch(data['id'] as String) ||
          !const ['state', 'enable', 'disable', 'confirm'].contains(data['action']) ||
          data['uid'] is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{20,128}$').hasMatch(data['uid'] as String)) {
        return null;
      }
      return NativePushRequest(data['id'], data['action'], data['uid']);
    } on FormatException {
      return null;
    }
  }
}
