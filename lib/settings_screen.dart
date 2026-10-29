import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_language.dart';
import 'ui_errors.dart';
import 'push_service.dart';
import 'push_platform.dart' as platform;
import 'chat_display_preferences.dart';
import 'translation_wallet.dart';

class SettingsScreen extends StatefulWidget {
  final bool showNotifications;
  const SettingsScreen({super.key, this.showNotifications = false});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  final _notificationSection = GlobalKey();
  late final _profile =
      FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .get();
  late final _contact =
      FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('private')
          .doc('contact')
          .get();
  String? _error;
  bool _busy = false;
  String _push = 'off';
  bool _pushLoading = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _readPush();
    if (widget.showNotifications) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _notificationSection.currentContext;
        if (mounted && target != null) {
          Scrollable.ensureVisible(target, alignment: 0.1);
        }
      });
    }
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(
          tr(context, 'settings'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr(context, 'account'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  future: _profile,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Text(tr(context, errorKey(snap.error!)));
                    }
                    final data = snap.data?.data();
                    final name =
                        data?['displayName'] as String? ??
                        data?['username'] as String? ??
                        '';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFE6EFFF),
                        child: Text(name.isEmpty ? '?' : name.characters.first),
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  future: _contact,
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
                const Divider(height: 32),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF5FF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const TranslationWallet(),
                ),
                const Divider(height: 24),
                Text(
                  tr(context, 'language'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                const LanguagePicker(),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(tr(context, 'saveLanguage')),
                ),
                if (_error != null)
                  Text(
                    tr(context, _error!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const Divider(height: 32),
                Text(
                  tr(context, 'messageDisplay'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const ChatDisplaySettings(),
                const Divider(height: 32),
                Text(
                  tr(context, 'pushTitle'),
                  key: _notificationSection,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
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
                const SizedBox(height: 8),
                Text(
                  tr(context, 'pushTrial'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Divider(height: 32),
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
      Text(tr(context, kIsWeb ? 'applePushHelp' : 'nativeApplePushHelp')),
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
