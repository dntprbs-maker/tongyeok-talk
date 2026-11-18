import 'dart:convert';
import 'dart:math';
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
  Future<void>? _initialization;

  Future<void> _initialize() =>
      _initialization ??= () async {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(options: DefaultFirebaseOptions.ios);
        }
      }();

  Future<String> run(String action, String uid) async {
    await _initialize();
    final prefs = await SharedPreferences.getInstance();
    final messaging = FirebaseMessaging.instance;
    final owner = prefs.getString(_owner);
    // Invalidate the old account's token before another account can enable it.
    if (owner != null && owner != uid) {
      await messaging.deleteToken();
      await prefs.remove(_owner);
      await prefs.remove(_token);
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
      return jsonEncode({'deviceId': device});
    }
    final settings =
        action == 'enable'
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
    if (await messaging.getAPNSToken() == null) return 'unsupported';
    final token = await messaging.getToken();
    if (token == null) return 'off';
    if (action == 'state') {
      return prefs.getString(_owner) == uid && prefs.getString(_token) == token
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
