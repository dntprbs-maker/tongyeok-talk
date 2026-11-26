import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app_language.dart';
import 'account_switch_menu.dart';
import 'push_service.dart';
import 'session_sign_out.dart';
import 'settings_screen.dart';

const _operatorUid = String.fromEnvironment('TONGYEOK_QA_OPERATOR_UID');

Future<bool> isQaTestSession(User user) async {
  if (!kIsWeb || _operatorUid.isEmpty || user.uid == _operatorUid) return false;
  try {
    final proof = await user.getIdTokenResult();
    final role = proof.claims?['tongyeokQaRole'];
    return proof.signInProvider == 'custom' &&
        (role == 'korean' || role == 'mongolian');
  } catch (_) {
    return false;
  }
}

class QaAccountSwitcher extends StatefulWidget {
  const QaAccountSwitcher({super.key, required this.user});

  final User user;

  @override
  State<QaAccountSwitcher> createState() => _QaAccountSwitcherState();
}

class _QaAccountSwitcherState extends State<QaAccountSwitcher> {
  late final _role = _loadRole();
  bool _busy = false;

  Future<Map<String, dynamic>> _call(String purpose, {String? target}) async {
    final token = await widget.user.getIdToken();
    if (token == null ||
        FirebaseAuth.instance.currentUser?.uid != widget.user.uid) {
      throw StateError('Session changed');
    }
    final response = await http
        .post(
          Uri.base.resolve('/review-auth'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'purpose': purpose,
            if (target != null) 'target': target,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('Verification access unavailable');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<String?> _loadRole() async {
    if (!kIsWeb || _operatorUid.isEmpty) return null;
    if (widget.user.uid != _operatorUid &&
        !await isQaTestSession(widget.user)) {
      return null;
    }
    try {
      return (await _call('qa-access'))['role'] as String?;
    } catch (_) {
      return null;
    }
  }

  String _label(String role) => tr(context, switch (role) {
    'korean' => 'qaKorean',
    'mongolian' => 'qaMongolian',
    _ => 'qaAdministrator',
  });

  Future<void> _select(String role, String target) async {
    if (_busy) return;
    if (role == target) {
      if (role == 'administrator') {
        final selected = await showDialog<String>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: Text(tr(context, 'qaAdministrator')),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final mode in ['korean', 'mongolian'])
                      ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text(_label(mode)),
                        onTap: () => Navigator.pop(context, mode),
                      ),
                    ListTile(
                      leading: const Icon(Icons.settings_outlined),
                      title: Text(tr(context, 'settings')),
                      onTap: () => Navigator.pop(context, 'settings'),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr(context, 'chatCreditClose')),
                  ),
                ],
              ),
        );
        if (selected == null || !mounted) return;
        if (selected == 'settings') {
          await Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          );
        } else {
          await _select(role, selected);
        }
      }
      return;
    }
    if (target == 'administrator') {
      final approved = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text(tr(context, 'qaAdministrator')),
              content: Text(tr(context, 'qaAdminLogin')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(tr(context, 'cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(tr(context, 'signIn')),
                ),
              ],
            ),
      );
      if (approved != true || !mounted || _busy) return;
    }
    setState(() => _busy = true);
    try {
      final auth = FirebaseAuth.instance;
      final navigator = Navigator.of(context);
      if (target == 'administrator') {
        await signOutSession(
          disableNotifications: PushService.disable,
          signOut: auth.signOut,
        );
        if (mounted) navigator.pushNamedAndRemoveUntil('/auth', (_) => false);
        return;
      }
      final token =
          (await _call('qa-switch', target: target))['token'] as String;
      if (!mounted) return;
      await signOutSession(
        disableNotifications: PushService.disable,
        signOut: () async {
          if (auth.currentUser?.uid != widget.user.uid) {
            throw StateError('Session changed');
          }
          await auth.signInWithCustomToken(token);
        },
      );
      if (!mounted) return;
      navigator.pushNamedAndRemoveUntil('/recentConversations', (_) => false);
      try {
        await AppLanguage.instance.select(target == 'korean' ? 'ko' : 'mn');
      } catch (_) {
        // The account switch is complete even if saving display preferences fails.
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(tr(context, 'qaSwitchError'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: _role,
    builder: (context, snapshot) {
      final role = snapshot.data;
      if (role == null) return const SizedBox.shrink();
      return AccountSwitchMenu(
        enabled: !_busy,
        selected: role,
        labels: {
          for (final target in ['korean', 'mongolian', 'administrator'])
            target: _label(target),
        },
        tooltip: tr(context, 'qaSwitch'),
        onSelected: (target) => _select(role, target),
      );
    },
  );
}
