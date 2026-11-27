import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'app_language.dart';
import 'auth_service.dart';
import 'phone_identity.dart';
import 'referral_screen.dart';
import 'qa_account_switcher.dart';

class RegisterPhoneScreen extends StatefulWidget {
  const RegisterPhoneScreen({super.key});

  @override
  State<RegisterPhoneScreen> createState() => _RegisterPhoneScreenState();
}

class _RegisterPhoneScreenState extends State<RegisterPhoneScreen> {
  final _number = TextEditingController();
  final _inviteCode = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _showInviteCode = false;

  @override
  void dispose() {
    _number.dispose();
    _inviteCode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final phone = PhoneIdentity.parse(_number.text);
      final enteredCode = _inviteCode.text.trim();
      final code = enteredCode.isNotEmpty
          ? enteredCode.toUpperCase()
          : await pendingReferral();
      if (code != null) await referralRequest('register', code: code);
      await AuthService().registerPhone(phone);
      if (code != null) await clearReferral();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/recentConversations',
          (_) => false,
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = switch (error) {
          FormatException() => 'registrationPhoneInvalid',
          StateError(message: 'phoneInUse') => 'phoneInUse',
          StateError(message: 'invalid_referral_code') =>
            'invalid_referral_code',
          StateError(message: 'referral_role_mismatch') =>
            'referral_role_mismatch',
          StateError(message: 'referral_already_registered') =>
            'referral_already_registered',
          _ => 'registrationFailed',
        };
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mn = LanguageScope.of(context).code == 'mn';
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'registerPhone'))),
      floatingActionButton: switch (FirebaseAuth.instance.currentUser) {
        final User user => QaAccountSwitcher(user: user),
        null => null,
      },
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(tr(context, 'registerPhoneHelp')),
            const SizedBox(height: 16),
            TextField(
              controller: _number,
              enabled: !_busy,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: tr(context, 'phone'),
                hintText: '010-1234-5678 / +976 99112233',
              ),
            ),
            if (_showInviteCode)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextField(
                  controller: _inviteCode,
                  enabled: !_busy,
                  autocorrect: false,
                  maxLength: 16,
                  decoration: InputDecoration(
                    labelText: mn ? 'Урилгын код (заавал биш)' : '초대 코드 (선택)',
                  ),
                ),
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _showInviteCode = true),
                  child: Text(mn ? 'Урилгын код оруулах' : '초대 코드 입력'),
                ),
              ),
            if (_error != null)
              Text(
                referralRegistrationError(context, _error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(tr(context, 'savePhoneRegistration')),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      await AuthService().signOut();
                      if (context.mounted) {
                        Navigator.pushNamedAndRemoveUntil(
                          context,
                          '/',
                          (_) => false,
                        );
                      }
                    },
              child: Text(tr(context, 'signOut')),
            ),
          ],
        ),
      ),
    );
  }
}
