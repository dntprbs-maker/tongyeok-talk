// lib/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Sign up with email, password, and username.
  Future<UserCredential> signUp(
    String email,
    String password,
    String username,
    String preferredLanguage,
  ) async {
    // Check if the username is already taken
    final QuerySnapshot result =
        await _firestore
            .collection('users')
            .where('username', isEqualTo: username)
            .get();

    if (result.docs.isNotEmpty) {
      throw Exception('Username already taken.');
    }

    try {
      // Create the user with Firebase Auth.
      UserCredential cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Save the user profile in Firestore
      await _firestore.collection('users').doc(cred.user!.uid).set({
        'username': username,
        'preferredLanguage': preferredLanguage,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return cred;
    } catch (e) {
      rethrow;
    }
  }

  // Sign in with email and password.
  Future<UserCredential> signIn(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return result;
    } catch (e) {
      rethrow;
    }
  }

  // Sign out.
  Future<void> signOut() async {
    await _auth.signOut();
  }
}
