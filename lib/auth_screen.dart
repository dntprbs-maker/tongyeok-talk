import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'phone_identity.dart';
import 'app_language.dart';
import 'brand.dart';
import 'ui_errors.dart';

class AuthScreen extends StatefulWidget {
  final bool isSignUp;
  const AuthScreen({super.key, this.isSignUp = false});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _phone = TextEditingController(),
      _password = TextEditingController();
  late bool _signUp;
  bool _busy = false, _obscure = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _signUp = widget.isSignUp;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final phone = PhoneIdentity.parseKorean(_phone.text);
      final lang = AppLanguage.instance.profileLanguage;
      if (_signUp) {
        await AuthService().signUp(_name.text, phone, _password.text, lang);
      } else {
        await AuthService().signIn(phone, _password.text, lang);
      }
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/recentConversations',
          (_) => false,
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorKey(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr(context, _signUp ? 'signUpTitle' : 'signInTitle')),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
            child: AutofillGroup(
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const LanguagePicker(),
                    const SizedBox(height: 24),
                    const BrandHeader(compact: true),
                    const SizedBox(height: 24),
                    if (_signUp) ...[
                      TextFormField(
                        key: const ValueKey('signup-name'),
                        controller: _name,
                        enabled: !_busy,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.nickname],
                        maxLength: 40,
                        decoration: InputDecoration(
                          labelText: tr(context, 'name'),
                          helperText: tr(context, 'nameHint'),
                          prefixIcon: const Icon(Icons.person_outline),
                        ),
                        validator:
                            (v) =>
                                v == null ||
                                        v.trim().isEmpty ||
                                        v.trim().length > 40
                                    ? tr(context, 'nameRequired')
                                    : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      key: const ValueKey('auth-phone'),
                      controller: _phone,
                      enabled: !_busy,
                      keyboardType: TextInputType.phone,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: tr(context, 'phone'),
                        hintText: '010-1234-5678',
                        prefixIcon: const Icon(Icons.phone_outlined),
                      ),
                      validator: (v) {
                        try {
                          PhoneIdentity.parseKorean(v ?? '');
                          return null;
                        } catch (_) {
                          return tr(context, 'phoneInvalid');
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const ValueKey('auth-password'),
                      controller: _password,
                      enabled: !_busy,
                      obscureText: _obscure,
                      autofillHints: [
                        _signUp
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: tr(context, 'password'),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: tr(
                            context,
                            _obscure ? 'showPassword' : 'hidePassword',
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator:
                          (v) =>
                              v == null || v.isEmpty
                                  ? tr(context, 'passwordRequired')
                                  : (_signUp && v.length < 6
                                      ? tr(context, 'passwordShort')
                                      : null),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      tr(context, 'phoneNotice'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          tr(context, _error!),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    FilledButton(
                      key: const ValueKey('auth-submit'),
                      onPressed: _busy ? null : _submit,
                      child:
                          _busy
                              ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : Text(
                                tr(context, _signUp ? 'signUp' : 'signIn'),
                              ),
                    ),
                    TextButton(
                      onPressed:
                          _busy
                              ? null
                              : () => setState(() {
                                _signUp = !_signUp;
                                _error = null;
                                _form.currentState!.reset();
                              }),
                      child: Text(
                        tr(context, _signUp ? 'alreadyAccount' : 'newAccount'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
