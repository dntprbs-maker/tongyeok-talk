import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_language.dart';
import 'auth_service.dart';
import 'phone_identity.dart';

class RegisterPhoneScreen extends StatefulWidget {
  const RegisterPhoneScreen({super.key});

  @override
  State<RegisterPhoneScreen> createState() => _RegisterPhoneScreenState();
}

class _RegisterPhoneScreenState extends State<RegisterPhoneScreen> {
  final _number = TextEditingController();
  final _code = TextEditingController();
  PhoneIdentity? _phone;
  String? _verificationId;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _number.text = FirebaseAuth.instance.currentUser?.phoneNumber ?? '';
  }

  @override
  void dispose() {
    _number.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = _verificationId;
      if (id != null) {
        await _complete(
          PhoneAuthProvider.credential(
            verificationId: id,
            smsCode: _code.text.trim(),
          ),
        );
        return;
      }
      final phone = PhoneIdentity.parse(_number.text);
      _phone = phone;
      await AuthService().checkPhoneAvailability(phone);
      if (FirebaseAuth.instance.currentUser?.phoneNumber == phone.e164) {
        await _complete(null);
        return;
      }
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone.e164,
        verificationCompleted: (_) {},
        verificationFailed: _fail,
        codeSent: (id, _) {
          if (!mounted) return;
          setState(() {
            _verificationId = id;
            _busy = false;
          });
        },
        codeAutoRetrievalTimeout: (_) {},
      );
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> _complete(PhoneAuthCredential? code) async {
    await AuthService().registerVerifiedPhone(_phone!, code);
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/recentConversations',
        (_) => false,
      );
    }
  }

  void _fail(Object error) {
    if (!mounted) return;
    final key = switch (error) {
      FormatException() => 'registrationPhoneInvalid',
      StateError(message: 'phoneInUse') => 'phoneInUse',
      FirebaseAuthException(code: 'credential-already-in-use') => 'phoneInUse',
      FirebaseAuthException(code: 'invalid-verification-code') =>
        'registrationCodeInvalid',
      FirebaseAuthException(code: 'session-expired') =>
        'registrationCodeInvalid',
      _ => 'registrationFailed',
    };
    setState(() {
      _busy = false;
      _error = key;
    });
  }

  @override
  Widget build(BuildContext context) {
    final codeSent = _verificationId != null;
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'registerPhone'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(tr(context, 'registerPhoneHelp')),
            const SizedBox(height: 16),
            TextField(
              controller: _number,
              enabled: !_busy && !codeSent,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              decoration: InputDecoration(
                labelText: tr(context, 'phone'),
                hintText: '010-1234-5678 / +976 99112233',
              ),
            ),
            if (codeSent)
              TextField(
                controller: _code,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: tr(context, 'registrationCode'),
                ),
              ),
            if (_error != null)
              Text(
                tr(context, _error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(
                tr(
                  context,
                  codeSent ? 'confirmRegistrationCode' : 'sendRegistrationCode',
                ),
              ),
            ),
            if (codeSent)
              TextButton(
                onPressed:
                    _busy
                        ? null
                        : () => setState(() {
                          _verificationId = null;
                          _error = null;
                          _code.clear();
                        }),
                child: Text(tr(context, 'resetRegistrationCode')),
              ),
            TextButton(
              onPressed:
                  _busy
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
