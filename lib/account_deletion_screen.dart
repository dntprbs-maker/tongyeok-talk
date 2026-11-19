import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'app_language.dart';
import 'reward_ad_service.dart';
import 'ui_errors.dart';

const accountDeletionHelpUrl =
    'https://asia-northeast3-tongyeok-talk-lab-20261024.cloudfunctions.net/rewardApi/account-deletion';

class AccountDeletionScreen extends StatefulWidget {
  const AccountDeletionScreen({super.key});
  @override
  State<AccountDeletionScreen> createState() => _AccountDeletionScreenState();
}

class _AccountDeletionScreenState extends State<AccountDeletionScreen> {
  final _password = TextEditingController();
  final _user = FirebaseAuth.instance.currentUser!;
  bool get _usesPassword =>
      !_user.providerData.any(
        (p) => p.providerId == 'google.com' || p.providerId == 'apple.com',
      );
  bool _confirmed = false, _busy = false;
  String? _error;
  late final _status =
      FirebaseFirestore.instance
          .collection('accountDeletionRequests')
          .doc(_user.uid)
          .snapshots();
  @override
  void dispose() {
    _password.clear();
    _password.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    if (_busy || !_confirmed || (_usesPassword && _password.text.isEmpty)) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final providers = _user.providerData.map((p) => p.providerId);
      if (providers.contains('google.com')) {
        await AuthService().reauthenticateGoogle(_user);
      } else if (providers.contains('apple.com')) {
        if (kIsWeb) {
          await _user.reauthenticateWithPopup(AppleAuthProvider());
        } else {
          await _user.reauthenticateWithProvider(AppleAuthProvider());
        }
      } else {
        final email = _user.email;
        if (email == null) throw StateError('deletionFailed');
        await _user.reauthenticateWithCredential(
          EmailAuthProvider.credential(email: email, password: _password.text),
        );
      }
      _password.clear();
      final token = await _user.getIdToken(true);
      final result = await http
          .post(
            Uri.parse('$rewardBackend/account-deletion-requests'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'policy': 'shared-messages-retained-v1',
              'confirmed': true,
            }),
          )
          .timeout(const Duration(seconds: 25));
      if (result.statusCode != 200) throw StateError('deletionFailed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'deletionRequested'))),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _error = error is StateError ? 'deletionFailed' : errorKey(error),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'deletionTitle'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          tr(context, 'deletionEffects'),
          style: const TextStyle(height: 1.6),
        ),
        const SizedBox(height: 16),
        Text(
          tr(context, 'deletionSharedMessages'),
          style: const TextStyle(fontWeight: FontWeight.w600, height: 1.6),
        ),
        const SizedBox(height: 16),
        Text(tr(context, 'deletionPersonalDataHelp')),
        const SizedBox(height: 16),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _status,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(tr(context, errorKey(snapshot.error!)));
            }
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final status = snapshot.data?.data()?['status'];
            if (status == 'requested' ||
                status == 'processing' ||
                status == 'completed') {
              return Text(
                tr(context, 'deletionRequested'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              );
            }
            return Column(
              children: [
                if (_usesPassword)
                  TextField(
                    controller: _password,
                    onChanged: (_) => setState(() {}),
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    enabled: !_busy,
                    decoration: InputDecoration(
                      labelText: tr(context, 'password'),
                    ),
                  ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _confirmed,
                  onChanged:
                      _busy
                          ? null
                          : (value) =>
                              setState(() => _confirmed = value ?? false),
                  title: Text(tr(context, 'deletionAcknowledge')),
                ),
                FilledButton(
                  onPressed:
                      _busy ||
                              !_confirmed ||
                              (_usesPassword && _password.text.isEmpty)
                          ? null
                          : _request,
                  child: Text(tr(context, 'deletionSubmit')),
                ),
              ],
            );
          },
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Text(tr(context, _error!), style: const TextStyle(color: Colors.red)),
        const Divider(height: 32),
        const SelectableText('dntprbs@gmail.com'),
        Text(tr(context, 'deletionExternalHelp')),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.copy),
          label: Text(tr(context, 'deletionCopyLink')),
          onPressed: () async {
            await Clipboard.setData(
              const ClipboardData(text: accountDeletionHelpUrl),
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(tr(context, 'deletionLinkCopied'))),
              );
            }
          },
        ),
      ],
    ),
  );
}
