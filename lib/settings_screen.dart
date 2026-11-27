import 'package:flutter/material.dart';
import 'referral_screen.dart';
import 'app_language.dart';
import 'app_update_tile_stub.dart'
    if (dart.library.js_interop) 'app_update_tile_web.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'ui_errors.dart';
import 'push_service.dart';
import 'push_platform.dart' as platform;
import 'chat_display_preferences.dart';
import 'account_deletion_screen.dart';
import 'session_sign_out.dart';
import 'contact_name_settings.dart';
import 'contact_names.dart';
import 'contact_names_platform.dart';

class SettingsScreen extends StatefulWidget {
  final bool showNotifications;
  const SettingsScreen({super.key, this.showNotifications = false});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  final _pushChanges = ValueNotifier<int>(0);
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
        if (mounted) _openPush();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pushChanges.dispose();
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
    } finally {
      if (mounted) _pushChanges.value++;
    }
  }

  Future<void> _togglePush() async {
    if (_busy || _pushLoading) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    _pushChanges.value++;
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
      if (mounted) {
        setState(() => _busy = false);
        _pushChanges.value++;
      }
    }
  }

  Future<void> _signOut() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await signOutSession(
        disableNotifications: PushService.disable,
        signOut: FirebaseAuth.instance.signOut,
      );
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
      }
    } catch (error) {
      if (mounted) setState(() => _error = errorKey(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showDetails(String title, Widget child) {
    showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(title),
            scrollable: true,
            content: SizedBox(width: 420, child: child),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(tr(dialogContext, 'chatCreditClose')),
              ),
            ],
          ),
    );
  }

  void _openAccount() => _showDetails(
    tr(context, 'account'),
    Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
            final preferredLanguage = data?['preferredLanguage'] as String?;
            final languageLabel =
                !snap.hasData
                    ? ''
                    : preferredLanguage == 'Mongolian'
                    ? tr(context, 'mn')
                    : preferredLanguage == 'Korean'
                    ? tr(context, 'ko')
                    : '';
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
              subtitle: Text(
                '${tr(context, 'signupLanguage')}: $languageLabel\n${tr(context, 'signupLanguageHelp')}',
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
                if (data != null) Text(data['phoneE164'] as String? ?? ''),
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
      ],
    ),
  );

  void _openPush() => _showDetails(
    tr(context, 'pushTitle'),
    AnimatedBuilder(
      animation: _pushChanges,
      builder:
          (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              if (_error == 'pushFailed')
                Text(
                  tr(context, 'pushFailed'),
                  style: const TextStyle(color: Colors.red),
                ),
            ],
          ),
    ),
  );

  void _showPage(Widget page) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FractionallySizedBox(heightFactor: .9, child: page),
    );
  }

  Future<void> _confirmSignOut() async {
    final result = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(tr(dialogContext, 'signOut')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(tr(dialogContext, 'cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(tr(dialogContext, 'signOut')),
              ),
            ],
          ),
    );
    if (mounted && result == true) await _signOut();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        tr(context, 'settings'),
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _item(Icons.person_outline, tr(context, 'account'), _openAccount),
            _screenLanguageOption(),
            if (androidContactsAvailable)
              _item(Icons.contacts_outlined, tr(context, 'contactNamesSettings'), () async {
                final user = FirebaseAuth.instance.currentUser;
                if (user == null) return;
                final contacts = ContactNames.forAccount(user.uid);
                if (!contacts.initialized) await contacts.initialize();
                if (context.mounted) await showContactNameSettings(context, contacts);
              }),
            _item(
              Icons.card_giftcard_outlined,
              referralLabel(context),
              () => _showPage(const ReferralScreen()),
            ),
            _item(
              Icons.chat_bubble_outline,
              tr(context, 'messageDisplay'),
              () => _showDetails(
                tr(context, 'messageDisplay'),
                const ChatDisplaySettings(),
              ),
            ),
            _item(
              Icons.notifications_outlined,
              tr(context, 'pushTitle'),
              _openPush,
            ),
            const Divider(),
            _item(
              Icons.logout,
              tr(context, 'signOut'),
              _busy ? null : _confirmSignOut,
            ),
            _item(
              Icons.person_remove_outlined,
              tr(context, 'deletionTitle'),
              _busy ? null : () => _showPage(const AccountDeletionScreen()),
            ),
            const AppUpdateTile(),
            if (_error != null && _error != 'pushFailed')
              Text(
                tr(context, _error!),
                style: const TextStyle(color: Colors.red),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _item(IconData icon, String title, VoidCallback? action) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    trailing: const Icon(Icons.chevron_right),
    onTap: action,
  );

  Widget _screenLanguageOption() {
    final uid = LanguageScope.of(context).displayLanguageAccount;
    if (uid == null) return const SizedBox.shrink();
    return _item(
      Icons.language,
      tr(context, 'interfaceLanguage'),
      () => _showDetails(
        tr(context, 'interfaceLanguage'),
        _InterfaceLanguageOptions(uid: uid),
      ),
    );
  }
}

class _InterfaceLanguageOptions extends StatelessWidget {
  const _InterfaceLanguageOptions({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    final language = LanguageScope.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr(context, 'interfaceLanguageHelp')),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final item in const {'ko': '한국어', 'mn': 'Монгол хэл'}.entries)
              ChoiceChip(
                label: Text(item.value),
                selected: language.displayCode == item.key,
                onSelected: (_) async {
                  await language.selectDisplayLanguage(uid, item.key);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
          ],
        ),
      ],
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
