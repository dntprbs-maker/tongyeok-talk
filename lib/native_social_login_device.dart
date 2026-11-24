import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'firebase_options.dart';
import 'native_social_login_bridge.dart';

class NativeSocialLoginDevice {
  static final _googleReady = GoogleSignIn.instance.initialize();
  static final _exchangeUrl = Uri.https(
    'asia-northeast3-tongyeok-talk-lab-20261024.cloudfunctions.net',
    '/mobileAuthExchange',
  );
  static Future<FirebaseApp>? _app;

  Future<String> signIn(NativeSocialRequest request) async {
    final app =
        await (_app ??= Firebase.initializeApp(
          name: 'mobileSocialLogin',
          options: DefaultFirebaseOptions.currentPlatform,
        ));
    final auth = FirebaseAuth.instanceFor(app: app);
    await auth.signOut();
    try {
      final provider = request.provider;
      final legacyToken = request.legacyToken;
      if (legacyToken != null) {
        final ticket = await _exchange(legacyToken, provider, 'start-link');
        final existing = (await auth.signInWithCustomToken(ticket)).user!;
        if (provider == NativeSocialProvider.google) {
          await existing.linkWithCredential(await _acquireGoogleCredential());
        } else {
          await existing.linkWithProvider(
            AppleAuthProvider()..addScope('name'),
          );
        }
        final idToken = await existing.getIdToken(true);
        if (idToken == null) throw StateError('socialLoginError');
        return await _exchange(idToken, provider, 'finish-link');
      }
      final result =
          provider == NativeSocialProvider.google
              ? await auth.signInWithCredential(
                await _acquireGoogleCredential(),
              )
              : await auth.signInWithProvider(
                AppleAuthProvider()..addScope('name'),
              );
      if (request.expectedUid != null &&
          request.expectedUid != result.user?.uid) {
        throw StateError('socialLoginError');
      }
      final idToken = await result.user?.getIdToken();
      if (idToken == null) throw StateError('socialLoginError');
      final customToken = await _exchange(idToken, provider, 'sign-in');
      if (provider == NativeSocialProvider.apple &&
          request.expectedUid != null) {
        await _revokeAppleToken(auth, result, idToken);
      }
      return customToken;
    } finally {
      await auth.signOut();
    }
  }

  Future<void> _revokeAppleToken(
    FirebaseAuth auth,
    UserCredential result,
    String idToken,
  ) async {
    try {
      final code = result.additionalUserInfo?.authorizationCode;
      if (defaultTargetPlatform == TargetPlatform.iOS && code != null) {
        await auth.revokeTokenWithAuthorizationCode(code);
        return;
      }
      final appleToken = result.credential?.accessToken;
      if (appleToken == null) return;
      await http
          .post(
            Uri.https(
              'identitytoolkit.googleapis.com',
              '/v2/accounts:revokeToken',
              {'key': auth.app.options.apiKey},
            ),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'providerId': 'apple.com',
              'tokenType': 'ACCESS_TOKEN',
              'token': appleToken,
              'idToken': idToken,
            }),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Token revocation must not block the user's account deletion request.
    }
  }

  Future<String> _exchange(
    String idToken,
    NativeSocialProvider provider,
    String purpose,
  ) async {
    final response = await http
        .post(
          _exchangeUrl,
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'provider': '${provider.name}.com',
            'purpose': purpose,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw StateError('socialLoginError');
    final body = jsonDecode(response.body);
    final token = body is Map<String, dynamic> ? body['token'] : null;
    if (token is! String || token.isEmpty) throw StateError('socialLoginError');
    return token;
  }

  static Future<OAuthCredential> _acquireGoogleCredential() async {
    await _googleReady;
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) throw StateError('socialLoginError');
    return GoogleAuthProvider.credential(idToken: idToken);
  }
}
