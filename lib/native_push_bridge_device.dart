import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

/// The authenticated web app remains responsible for writing its own
/// pushDevices document. No web login credential crosses this bridge.
class NativePushBridgeDevice {
  static const _owner = 'tongyeok.shell.pushOwner';
  static const _device = 'tongyeok.shell.pushDevice';
  static const _token = 'tongyeok.shell.pushToken';
  static const _confirmed = 'tongyeok.shell.pushConfirmed';
  Future<void>? _initialization;
  bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _initialize() => _initialization ??= () async {
    if (!Firebase.apps.any((app) => app.name == '[DEFAULT]')) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    if (!_ios) return;
    // The implicit Flutter engine may register plugins after the iOS
    // launch notification used by older messaging plugins has passed.
    await const MethodChannel('tongyeok/pushRegistration')
        .invokeMethod<void>('register');
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
  }();

  Future<String> run(String action, String uid) async {
    await _initialize();
    debugPrint('TT_IOS_PUSH_INITIALIZED');
    final prefs = await SharedPreferences.getInstance();
    final messaging = FirebaseMessaging.instance;
    final owner = prefs.getString(_owner);
    // Invalidate the old account's token before another account can enable it.
    if (owner != null && owner != uid) {
      await messaging.deleteToken();
      await prefs.remove(_owner);
      await prefs.remove(_token);
      await prefs.remove(_confirmed);
    }
    var device = prefs.getString(_device);
    if (device == null) {
      device =
          'shell_${base64UrlEncode(List.generate(24, (_) => Random.secure().nextInt(256))).replaceAll('=', '')}';
      await prefs.setString(_device, device);
    }
    if (action == 'disable') {
      if (owner == uid) await messaging.deleteToken();
      await prefs.remove(_owner);
      await prefs.remove(_token);
      await prefs.remove(_confirmed);
      return jsonEncode({'deviceId': device});
    }
    // Enable is only a proposal. The authenticated web client acknowledges it
    // after its own Firestore write succeeds. A timed-out permission prompt or
    // navigation cannot otherwise leave a false "enabled" status behind.
    if (action == 'confirm') {
      if (prefs.getString(_owner) != uid || prefs.getString(_token) == null) {
        throw StateError('push_failed');
      }
      await prefs.setBool(_confirmed, true);
      return 'enabled';
    }
    if (action == 'enable') await prefs.remove(_confirmed);
    final settings = action == 'enable'
        ? await messaging.requestPermission(
            alert: true,
            badge: true,
            sound: true,
          )
        : await messaging.getNotificationSettings();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return 'denied';
    }
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      return 'off';
    }
    if (_ios) {
      var apns = await messaging.getAPNSToken();
      for (
        var attempt = 0;
        action == 'enable' && apns == null && attempt < 10;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        apns = await messaging.getAPNSToken();
      }
      if (apns == null) return action == 'state' ? 'off' : 'unsupported';
    }
    final token = await messaging.getToken();
    debugPrint('TT_IOS_PUSH_FCM_READY');
    if (token == null) return 'off';
    if (action == 'state') {
      return prefs.getString(_owner) == uid &&
              prefs.getString(_token) == token &&
              prefs.getBool(_confirmed) == true
          ? 'enabled'
          : 'off';
    }
    await prefs.setString(_owner, uid);
    await prefs.setString(_token, token);
    return jsonEncode({
      'deviceId': device,
      'subscription': {'transport': 'fcm', 'token': token},
    });
  }
}
