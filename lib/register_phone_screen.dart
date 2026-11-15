import 'package:flutter/material.dart';

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
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService().registerPhone(PhoneIdentity.parse(_number.text));
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
          _ => 'registrationFailed',
        };
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'registerPhone'))),
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
          if (_error != null)
            Text(
              tr(context, _error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(tr(context, 'savePhoneRegistration')),
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
