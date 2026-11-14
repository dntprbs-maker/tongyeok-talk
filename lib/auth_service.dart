import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'phone_identity.dart';

class AuthService {
  static final _googleReady = GoogleSignIn.instance.initialize();
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  Future<void> signInWithGoogle(String language, String fallbackName) async {
    await _googleReady;
    final account = await GoogleSignIn.instance.authenticate();
    final token = account.authentication.idToken;
    if (token == null) throw StateError('missingGoogleToken');
    final credential = await _auth.signInWithCredential(
      GoogleAuthProvider.credential(idToken: token),
    );
    await _prepareSocialProfile(credential, language, fallbackName);
  }

  Future<void> signInWithApple(String language, String fallbackName) async {
    final provider = AppleAuthProvider()..addScope('name');
    final credential = await _auth.signInWithProvider(provider);
    await _prepareSocialProfile(credential, language, fallbackName);
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
        if (profile.exists) {
          tx.update(ref, {'preferredLanguage': language});
        } else {
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
