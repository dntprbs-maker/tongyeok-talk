import 'dart:async';

/// Notification cleanup must not trap a user in a signed-in session.
/// Authentication failures still propagate so the UI cannot claim success.
Future<void> signOutSession({
  required Future<void> Function() disableNotifications,
  required Future<void> Function() signOut,
  Duration cleanupTimeout = const Duration(seconds: 5),
}) async {
  try {
    await disableNotifications().timeout(cleanupTimeout);
  } catch (_) {
    // Keep authentication sign-out available during notification/network errors.
  }
  await signOut();
}
