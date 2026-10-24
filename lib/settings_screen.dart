import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_language.dart';
import 'ui_errors.dart';
import 'push_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _error;
  bool _busy = false;
  String _push = 'off';
  @override
  void initState() {
    super.initState();
    PushService.state().then((value) {
      if (mounted) setState(() => _push = value);
    });
  }

  Future<void> _togglePush() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_push == 'enabled') {
        await PushService.disable();
        if (mounted) setState(() => _push = 'off');
      } else {
        final value = await PushService.enable();
        if (mounted) setState(() => _push = value);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'pushFailed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .update({'preferredLanguage': AppLanguage.instance.profileLanguage});
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(tr(context, 'saved'))));
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorKey(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'settings'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                tr(context, 'language'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              const LanguagePicker(),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(tr(context, 'save')),
              ),
              if (_error != null)
                Text(
                  tr(context, _error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const Divider(height: 48),
              Text(
                tr(context, 'pushTitle'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(tr(context, 'pushTrial')),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _togglePush,
                icon: Icon(
                  _push == 'enabled'
                      ? Icons.notifications_active
                      : Icons.notifications_none,
                ),
                label: Text(
                  tr(
                    context,
                    _push == 'enabled' ? 'pushDisable' : 'pushEnable',
                  ),
                ),
              ),
              Text(
                tr(
                  context,
                  _push == 'enabled'
                      ? 'pushEnabled'
                      : _push == 'denied'
                      ? 'pushDenied'
                      : _push == 'unsupported'
                      ? 'pushUnsupported'
                      : 'pushOff',
                ),
              ),
              const Divider(height: 48),
              Text(
                tr(context, 'account'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future:
                    FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .get(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Text(tr(context, errorKey(snap.error!)));
                  }
                  final data = snap.data?.data();
                  return Text(
                    data?['displayName'] as String? ??
                        data?['username'] as String? ??
                        '',
                  );
                },
              ),
              const SizedBox(height: 8),
              FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future:
                    FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .collection('private')
                        .doc('contact')
                        .get(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Text(tr(context, errorKey(snap.error!)));
                  }
                  final data = snap.data?.data();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (data != null)
                        Text(data['phoneE164'] as String? ?? ''),
                      const SizedBox(height: 8),
                      Text(
                        tr(
                          context,
                          data == null ? 'legacyAccount' : 'phoneUnverified',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 32),
              OutlinedButton.icon(
                icon: const Icon(Icons.logout),
                label: Text(tr(context, 'signOut')),
                onPressed: () async {
                  await PushService.disable();
                  await FirebaseAuth.instance.signOut();
                  if (context.mounted) {
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/',
                      (_) => false,
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
