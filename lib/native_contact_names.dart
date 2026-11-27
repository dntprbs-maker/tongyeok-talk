import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class NativeContactNames {
  static const _channel = MethodChannel('tongyeok/contacts');
  static final _endpoint = Uri.https(
    'asia-northeast3-tongyeok-talk-lab-20261024.cloudfunctions.net',
    '/contactMatchNumbers',
  );

  Future<Object?> request(Map<String, dynamic> request) async {
    final operation = request['op'];
    switch (operation) {
      case 'status':
      case 'enable':
        return _channel.invokeMethod<bool>(operation as String);
      case 'pick':
      case 'pickPhone':
        return _channel.invokeMethod<String>(operation as String);
      case 'lookup':
        if (await _channel.invokeMethod<bool>('status') != true) return {};
        final token = request['token'];
        final rooms = request['rooms'];
        if (token is! String ||
            token.length > 8192 ||
            !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(token) ||
            rooms is! List ||
            rooms.isEmpty ||
            rooms.length > 30 ||
            rooms.any(
              (id) =>
                  id is! String ||
                  !RegExp(r'^[A-Za-z0-9_-]{1,120}$').hasMatch(id),
            )) {
          return null;
        }
        final response = await http
            .post(
              _endpoint,
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({'roomIds': rooms}),
            )
            .timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) return null;
        final numbers = jsonDecode(response.body) as Map<String, dynamic>;
        if (numbers.isEmpty) return {};
        return _channel.invokeMapMethod<String, String>('lookup', numbers);
      default:
        return null;
    }
  }
}

String nativeContactNamesScript(String nonce) =>
    '''
(() => {
  if (window.top !== window) return;
  const nonce = ${jsonEncode(nonce)};
  const pending = new Map();
  let next = 0;
  window.tongyeokContactNames = (request) => new Promise(resolve => {
    if (pending.size >= 4) return resolve(null);
    const id = String(++next);
    const timer = setTimeout(() => {
      pending.delete(id);
      resolve(null);
    }, ['pick', 'pickPhone', 'enable'].includes(request.op) ? 120000 : 15000);
    pending.set(id, value => { clearTimeout(timer); resolve(value); });
    TongyeokNativeContactNames.postMessage(JSON.stringify({...request, nonce, id}));
  });
  window.__tongyeokContactNamesResult = (page, id, result) => {
    if (window.top !== window || page !== nonce) return;
    const finish = pending.get(id);
    pending.delete(id);
    finish?.(result);
  };
  window.dispatchEvent(new Event('tongyeok-contact-names-ready'));
})();
''';
