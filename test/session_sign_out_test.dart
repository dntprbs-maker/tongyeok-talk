import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridgechat/session_sign_out.dart';

void main() {
  test('normal sign-out revokes notifications before authentication', () async {
    final events = <String>[];
    await signOutSession(
      disableNotifications: () async => events.add('notifications'),
      signOut: () async => events.add('auth'),
    );
    expect(events, ['notifications', 'auth']);
  });

  test('notification failure cannot keep the user signed in', () async {
    var signedOut = false;
    await signOutSession(
      disableNotifications: () async => throw StateError('offline'),
      signOut: () async { signedOut = true; },
    );
    expect(signedOut, isTrue);
  });

  test('hung notification cleanup has a deadline and still signs out', () async {
    var signedOut = false;
    await signOutSession(
      disableNotifications: () => Completer<void>().future,
      signOut: () async { signedOut = true; },
      cleanupTimeout: Duration.zero,
    );
    expect(signedOut, isTrue);
  });

  test('authentication failure propagates instead of claiming sign-out', () async {
    await expectLater(signOutSession(
      disableNotifications: () async {},
      signOut: () async => throw StateError('auth_failure'),
    ), throwsStateError);
  });
}
