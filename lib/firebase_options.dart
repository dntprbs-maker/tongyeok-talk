// Public Firebase web app identifiers. Access is enforced by Auth and Firestore rules.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS ? ios : web;

  static const web = FirebaseOptions(
    apiKey: 'AIzaSyB7Nf9kYgJ9y0ubRGrg3sHA5tLw2qTLDsg',
    appId: '1:899237147853:web:1a642f5c91060c34b1e584',
    messagingSenderId: '899237147853',
    projectId: 'tongyeok-talk-lab-20261024',
    authDomain: 'tongyeok-talk-lab-20261024.firebaseapp.com',
    storageBucket: 'tongyeok-talk-lab-20261024.firebasestorage.app',
  );

  static const ios = FirebaseOptions(
    apiKey: 'AIzaSyBTWQdelprkMhWr2C9JaPhVQT6aOuEXcTo',
    appId: '1:899237147853:ios:72dd39e67441cb23b1e584',
    messagingSenderId: '899237147853',
    projectId: 'tongyeok-talk-lab-20261024',
    storageBucket: 'tongyeok-talk-lab-20261024.firebasestorage.app',
    iosBundleId: 'com.tongyeoktalk',
  );
}
