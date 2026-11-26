import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'contact_names_platform.dart';

class ContactNames extends ChangeNotifier {
  ContactNames._(this.uid);

  static ContactNames? _active;
  static ContactNames forAccount(String uid) {
    if (_active?.uid != uid) _active = ContactNames._(uid);
    return _active!;
  }

  final String uid;
  final _preferences = SharedPreferencesAsync();
  final _manual = <String, String>{};
  Map<String, String> _automatic = {};
  List<String> _peers = [];
  bool initialized = false;
  bool _refreshing = false, _refreshAgain = false;
  bool _enabled = false;

  bool get available => androidContactsAvailable;
  bool get automaticEnabled => _enabled;
  String get _key => 'androidContactNames.$uid';
  String _peerKey(String peer) => '$_key.name.$peer';
  DocumentReference<Map<String, dynamic>> get _consent =>
      FirebaseFirestore.instance.doc('users/$uid/private/contactMatchConsent');

  String? name(String peer) => _manual[peer] ?? _automatic[peer];
  bool hasManual(String peer) => _manual.containsKey(peer);
  Future<bool> get needsSetup async =>
      available && await _preferences.getBool('$_key.setup') != true;
  Future<void> markSetup() => _preferences.setBool('$_key.setup', true);

  Future<bool> readSharing() async =>
      (await _consent.get()).data()?['enabled'] == true;
  Future<void> setSharing(bool value) => _consent.set({'enabled': value});

  Future<void> initialize() async {
    if (!available) return;
    _enabled = await _preferences.getBool('$_key.auto') == true;
    initialized = true;
    notifyListeners();
  }

  Future<bool> enableAutomatic() async {
    if (!available) return false;
    _enabled = await requestAndroidContacts({'op': 'enable'}) == true;
    if (!_enabled) _automatic = {};
    await _preferences.setBool('$_key.auto', _enabled);
    notifyListeners();
    return _enabled;
  }

  Future<void> disableAutomatic() async {
    _enabled = false;
    _automatic = {};
    await _preferences.setBool('$_key.auto', false);
    notifyListeners();
  }

  Future<void> pick(String peer) async {
    final picked = await requestAndroidContacts({'op': 'pick'});
    if (picked is! String || picked.trim().isEmpty || !_isCurrent) return;
    final label = String.fromCharCodes(picked.trim().runes.take(100));
    await _preferences.setString(_peerKey(peer), label);
    _manual[peer] = label;
    notifyListeners();
  }

  Future<void> clear(String peer) async {
    await _preferences.remove(_peerKey(peer));
    _manual.remove(peer);
    notifyListeners();
  }

  bool get _isCurrent => FirebaseAuth.instance.currentUser?.uid == uid;

  Future<void> loadManualNames(List<String> peers) async {
    if (!available || listEquals(_peers, peers)) return;
    _peers = peers;
    for (final peer in peers) {
      final label = await _preferences.getString(_peerKey(peer));
      if (label != null) _manual.putIfAbsent(peer, () => label);
    }
    if (_isCurrent) notifyListeners();
  }

  List<String> _rooms = [];
  void setRooms(List<String> rooms) {
    if (listEquals(_rooms, rooms)) return;
    _rooms = rooms;
    refresh();
  }

  Future<void> refresh() async {
    if (!available || !_enabled || !_isCurrent) return;
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    try {
      final rooms = _rooms;
      final results = <String, String>{};
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null || !_isCurrent) return;
      for (
        var start = 0;
        start < rooms.length && _enabled && _isCurrent;
        start += 30
      ) {
        final result = await requestAndroidContacts({
          'op': 'lookup',
          'token': token,
          'rooms': rooms.sublist(start, math.min(start + 30, rooms.length)),
        });
        if (result is Map) {
          for (final entry in result.entries) {
            if (entry.key is String && entry.value is String) {
              results[entry.key as String] = entry.value as String;
            }
          }
        }
      }
      if (_enabled && _isCurrent) _automatic = results;
    } catch (_) {
      _automatic = {};
    } finally {
      _refreshing = false;
      if (_isCurrent) notifyListeners();
      if (_refreshAgain) {
        _refreshAgain = false;
        refresh();
      }
    }
  }
}
