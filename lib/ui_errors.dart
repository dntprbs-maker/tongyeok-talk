import 'package:firebase_core/firebase_core.dart';

String errorKey(Object error) {
  if (error is FormatException) return 'phoneInvalid';
  if (error is StateError && error.message == 'phoneInUse') return 'phoneInUse';
  if (error is StateError && error.message == 'profileMissing') {
    return 'profileMissing';
  }
  if (error is FirebaseException) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'phoneInUse';
      case 'wrong-password':
      case 'user-not-found':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return 'invalidLogin';
      case 'weak-password':
        return 'passwordShort';
      case 'network-request-failed':
      case 'unavailable':
        return 'networkError';
      case 'too-many-requests':
      case 'resource-exhausted':
        return 'tooManyAttempts';
      case 'permission-denied':
      case 'unauthenticated':
        return 'permissionError';
    }
  }
  return 'genericError';
}
