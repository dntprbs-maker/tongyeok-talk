import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'auth_service.dart';
import 'app_language.dart';
import 'brand.dart';

class AuthScreen extends StatefulWidget {
  final bool isSignUp;
  const AuthScreen({super.key, this.isSignUp = false});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _busy = false;
  String? _error;

  bool get _appleAvailable =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _submitSocial({required bool apple}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final language = AppLanguage.instance.profileLanguage;
      final name = tr(context, 'socialDefaultName');
      final service = AuthService();
      if (apple) {
        await service.signInWithApple(language, name);
      } else {
        await service.signInWithGoogle(language, name);
      }
      final user = FirebaseAuth.instance.currentUser!;
      final hasPhone = await service.hasRegisteredPhone(user);
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          hasPhone ? '/recentConversations' : '/registerPhone',
          (_) => false,
        );
      }
    } on GoogleSignInException catch (e) {
      if (mounted && e.code != GoogleSignInExceptionCode.canceled) {
        setState(() => _error = 'socialLoginError');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'socialLoginError');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr(context, widget.isSignUp ? 'signUpTitle' : 'signInTitle')),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const LanguagePicker(),
                const SizedBox(height: 24),
                const BrandHeader(compact: true),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: _busy ? null : () => _submitSocial(apple: false),
                  child: Text(tr(context, 'googleSignIn')),
                ),
                if (_appleAvailable)
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _submitSocial(apple: true),
                    icon: const Icon(Icons.apple),
                    label: Text(tr(context, 'appleSignIn')),
                  ),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      tr(context, _error!),
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
