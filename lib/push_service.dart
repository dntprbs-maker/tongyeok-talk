import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_language.dart';
import 'push_platform.dart' as platform;

class PushService {
  static Future<String> state() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null ? 'off' : platform.pushState(uid);
  }

  static Future<String> enable() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final result = await platform.enablePush(uid);
    if (!result.startsWith('{')) return result;
    final data = jsonDecode(result) as Map<String, dynamic>;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('pushDevices')
          .doc(data['deviceId'] as String)
          .set({
            'subscriptionJson': jsonEncode(data['subscription']),
            'enabled': true,
            'language': AppLanguage.instance.code,
            'updatedAt': FieldValue.serverTimestamp(),
          });
      return 'enabled';
    } catch (_) {
      await platform.disablePush(uid);
      rethrow;
    }
  }

  static Future<void> disable() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final result = await platform.disablePush(uid);
    if (result.startsWith('{')) {
      final data = jsonDecode(result) as Map<String, dynamic>;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('pushDevices')
          .doc(data['deviceId'] as String)
          .update({
            'enabled': false,
            'updatedAt': FieldValue.serverTimestamp(),
          });
    }
  }
}
