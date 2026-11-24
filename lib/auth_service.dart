import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

import 'phone_identity.dart';
import 'firebase_options.dart';
import 'social_login_platform.dart';

class AuthService {
  static final _googleReady = GoogleSignIn.instance.initialize();
  static Future<FirebaseApp>? _legacyApp;
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  Future<bool> hasRegisteredPhone(User user) async {
    final data =
        (await _db
                .collection('users')
                .doc(user.uid)
                .collection('private')
                .doc('contact')
                .get())
            .data();
    return data?['phoneE164'] is String;
  }

  Future<void> registerPhone(PhoneIdentity phone) async {
    final user = _auth.currentUser!;
    final lookup = _db.collection('phoneDirectory').doc(phone.directoryKey);
    final contact = _db
        .collection('users')
        .doc(user.uid)
        .collection('private')
        .doc('contact');
    await _db.runTransaction((tx) async {
      final directory = await tx.get(lookup);
      final currentContact = await tx.get(contact);
      if (directory.exists && directory.data()?['uid'] != user.uid) {
        throw StateError('phoneInUse');
      }
      if (currentContact.exists &&
          currentContact.data()?['phoneE164'] != phone.e164) {
        throw StateError('phoneInUse');
      }
      if (!directory.exists) tx.set(lookup, {'uid': user.uid});
      if (!currentContact.exists) {
        tx.set(contact, {'phoneE164': phone.e164, 'phoneVerified': false});
      }
    });
  }

  Future<void> signInWithGoogle(String language, String fallbackName) async {
    final credential =
        nativeSocialLoginAvailable
            ? await _auth.signInWithCustomToken(
              await requestNativeSocialLogin('google'),
            )
            : kIsWeb
            ? await _auth.signInWithPopup(GoogleAuthProvider())
            : await _auth.signInWithCredential(await _googleCredential());
    await _prepareSocialProfile(credential, language, fallbackName);
  }

  Future<AuthCredential> _googleCredential() async {
    await _googleReady;
    final account = await GoogleSignIn.instance.authenticate();
    final token = account.authentication.idToken;
    if (token == null) throw StateError('missingGoogleToken');
    return GoogleAuthProvider.credential(idToken: token);
  }

  Future<void> reauthenticateGoogle(User user) async {
    if (nativeSocialLoginAvailable) {
      await _authenticateExistingWebUser('google', user);
    } else if (kIsWeb) {
      await user.reauthenticateWithPopup(GoogleAuthProvider());
    } else {
      await user.reauthenticateWithCredential(await _googleCredential());
    }
  }

  Future<void> reauthenticateApple(User user) async {
    if (nativeSocialLoginAvailable) {
      await _authenticateExistingWebUser('apple', user);
    } else if (kIsWeb) {
      await user.reauthenticateWithPopup(AppleAuthProvider());
    } else {
      await user.reauthenticateWithProvider(AppleAuthProvider());
    }
  }

  Future<void> _authenticateExistingWebUser(String provider, User user) async {
    final token = await requestNativeSocialLogin(
      provider,
      expectedUid: user.uid,
    );
    if (_auth.currentUser?.uid != user.uid) {
      throw StateError('socialLoginError');
    }
    await _auth.signInWithCustomToken(token);
  }

  Future<void> signInWithApple(String language, String fallbackName) async {
    final provider = AppleAuthProvider()..addScope('name');
    final credential =
        nativeSocialLoginAvailable
            ? await _auth.signInWithCustomToken(
              await requestNativeSocialLogin('apple'),
            )
            : kIsWeb
            ? await _auth.signInWithPopup(provider)
            : await _auth.signInWithProvider(provider);
    await _prepareSocialProfile(credential, language, fallbackName);
  }

  Future<FirebaseAuth> _legacyAuth() async {
    final app =
        await (_legacyApp ??= Firebase.initializeApp(
          name: 'legacyAccountLink',
          options: DefaultFirebaseOptions.currentPlatform,
        ));
    final auth = FirebaseAuth.instanceFor(app: app);
    if (kIsWeb) await auth.setPersistence(Persistence.NONE);
    return auth;
  }

  Future<void> signInForReview(PhoneIdentity phone, String password) async {
    final auth = await _legacyAuth();
    try {
      final verified =
          (await auth.signInWithEmailAndPassword(
            email: phone.authAlias,
            password: password,
          )).user!;
      final proof = await verified.getIdToken();
      if (proof == null) throw StateError('reviewLoginError');
      final response = await http
          .post(
            Uri.base.resolve('/review-auth'),
            headers: {
              'Authorization': 'Bearer $proof',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'purpose': 'review-sign-in'}),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) throw StateError('reviewLoginError');
      final token =
          (jsonDecode(response.body) as Map<String, dynamic>)['token'];
      if (token is! String || token.isEmpty) {
        throw StateError('reviewLoginError');
      }
      final signedIn = await _auth.signInWithCustomToken(token);
      if (signedIn.user?.uid != verified.uid) {
        await _auth.signOut();
        throw StateError('reviewLoginError');
      }
    } finally {
      await auth.signOut();
    }
  }

  Future<void> linkLegacyAccount({
    required PhoneIdentity phone,
    required String password,
    required bool apple,
  }) async {
    final auth = await _legacyAuth();
    try {
      final old =
          (await auth.signInWithEmailAndPassword(
            email: phone.authAlias,
            password: password,
          )).user!;
      final profile =
          await FirebaseFirestore.instanceFor(
            app: auth.app,
          ).collection('users').doc(old.uid).get();
      if (!profile.exists || profile.data()?['deleted'] == true) {
        throw StateError('profileMissing');
      }
      if (nativeSocialLoginAvailable) {
        final proof = await old.getIdToken();
        if (proof == null) throw StateError('socialLoginError');
        final token = await requestNativeSocialLogin(
          apple ? 'apple' : 'google',
          legacyToken: proof,
        );
        final linked = await _auth.signInWithCustomToken(token);
        if (linked.user?.uid != old.uid) {
          await _auth.signOut();
          throw StateError('socialLoginError');
        }
        return;
      }
      final provider = apple ? AppleAuthProvider() : GoogleAuthProvider();
      if (kIsWeb) {
        await old.linkWithPopup(provider);
      } else {
        await old.linkWithProvider(provider);
      }
      // The linked provider is used from the ordinary login screen next.
    } finally {
      await auth.signOut();
    }
  }

  Future<void> _prepareSocialProfile(
    UserCredential credential,
    String language,
    String fallbackName,
  ) async {
    final user = credential.user!;
    final ref = _db.collection('users').doc(user.uid);
    final name = user.displayName?.trim() ?? '';
    try {
      await _db.runTransaction((tx) async {
        final profile = await tx.get(ref);
        if (profile.data()?['deleted'] == true) {
          throw StateError('accountDeleted');
        }
        if (!profile.exists) {
          tx.set(ref, {
            'displayName':
                name.isEmpty
                    ? fallbackName
                    : String.fromCharCodes(name.runes.take(40)),
            'preferredLanguage': language,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } catch (_) {
      if (_auth.currentUser?.uid == user.uid) await _auth.signOut();
      rethrow;
    }
  }

  Future<UserCredential> signUp(
    String name,
    PhoneIdentity phone,
    String password,
    String language,
  ) async {
    UserCredential credential;
    try {
      credential = await _auth.createUserWithEmailAndPassword(
        email: phone.authAlias,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code != 'email-already-in-use') rethrow;
      // Recover a registration interrupted before its atomic profile write.
      try {
        credential = await _auth.signInWithEmailAndPassword(
          email: phone.authAlias,
          password: password,
        );
      } on FirebaseAuthException {
        throw StateError('phoneInUse');
      }
      if ((await _db.collection('users').doc(credential.user!.uid).get())
          .exists) {
        throw StateError('phoneInUse');
      }
    }
    final uid = credential.user!.uid;
    await _db.runTransaction((tx) async {
      final lookup = _db.collection('phoneDirectory').doc(phone.directoryKey);
      final old = await tx.get(lookup);
      if (old.exists && old.data()?['uid'] != uid) {
        throw StateError('phoneInUse');
      }
      if (!old.exists) tx.set(lookup, {'uid': uid});
      tx.set(_db.collection('users').doc(uid), {
        'displayName': name.trim(),
        'preferredLanguage': language,
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.set(
        _db.collection('users').doc(uid).collection('private').doc('contact'),
        {'phoneE164': phone.e164, 'phoneVerified': false},
      );
    });
    return credential;
  }

  Future<UserCredential> signIn(
    PhoneIdentity phone,
    String password,
    String language,
  ) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: phone.authAlias,
      password: password,
    );
    final ref = _db.collection('users').doc(credential.user!.uid);
    if (!(await ref.get()).exists) throw StateError('profileMissing');
    await ref.update({'preferredLanguage': language});
    return credential;
  }

  Future<Map<String, dynamic>?> findByPhone(PhoneIdentity phone) async {
    final directory =
        await _db.collection('phoneDirectory').doc(phone.directoryKey).get();
    final uid = directory.data()?['uid'] as String?;
    if (uid == null) return null;
    final profile = await _db.collection('users').doc(uid).get();
    if (!profile.exists) return null;
    return {'uid': uid, ...profile.data()!};
  }

  Future<void> signOut() => _auth.signOut();
}
