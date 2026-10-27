import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_language.dart';
import 'ui_errors.dart';
import 'push_service.dart';
import 'push_platform.dart' as platform;
import 'chat_display_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  String? _error;
  bool _busy = false;
  String _push = 'off';
  bool _pushLoading = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _readPush();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _readPush();
  }

  Future<void> _readPush() async {
    try {
      final value = await PushService.state();
      if (mounted) {
        setState(() {
          _push = value;
          _pushLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _pushLoading = false;
          _error = 'pushFailed';
        });
      }
    }
  }

  Future<void> _togglePush() async {
    if (_busy || _pushLoading) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_push == 'enabled') {
        if (platform.appleMobile) return;
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
              const Divider(height: 32),
              const ChatDisplaySettings(),
              const Divider(height: 32),
              Text(
                tr(context, 'pushTitle'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(tr(context, 'pushTrial')),
              const SizedBox(height: 12),
              if (platform.appleMobile)
                ApplePushEnableControl(
                  status: _push,
                  busy: _busy || _pushLoading,
                  onEnable: _togglePush,
                )
              else
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr(context, 'pushReception')),
                  subtitle: Text(tr(context, 'pushDeviceOnly')),
                  secondary: Icon(
                    _push == 'enabled'
                        ? Icons.notifications_active
                        : Icons.notifications_off_outlined,
                  ),
                  value: _push == 'enabled',
                  onChanged:
                      _busy || _pushLoading || _push == 'unsupported'
                          ? null
                          : (_) => _togglePush(),
                ),
              if (_busy || _pushLoading) const LinearProgressIndicator(),
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

/// iPhone/iPad offers enabling only; permission remains under iOS control.
class ApplePushEnableControl extends StatelessWidget {
  final String status;
  final bool busy;
  final VoidCallback onEnable;
  const ApplePushEnableControl({
    super.key,
    required this.status,
    required this.busy,
    required this.onEnable,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(tr(context, 'applePushHelp')),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed:
            busy || status == 'enabled' || status == 'unsupported'
                ? null
                : onEnable,
        icon: Icon(
          status == 'enabled'
              ? Icons.check_circle_outline
              : Icons.notifications_active_outlined,
        ),
        label: Text(
          tr(context, status == 'enabled' ? 'pushEnabled' : 'pushEnable'),
        ),
      ),
    ],
  );
}
