import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_language.dart';

String profileDisplayName(Map<String, dynamic>? profile) {
  if (profile?['deleted'] == true) {
    return AppLanguage.instance.text('deletedUser');
  }
  return profile?['displayName'] as String? ??
      profile?['username'] as String? ??
      AppLanguage.instance.text('unknownUser');
}

/// A live profile read prevents an open chat retaining the previous identity.
class ProfileName extends StatelessWidget {
  final String uid;
  final TextStyle? style;
  final String? fallback;
  const ProfileName({super.key, required this.uid, this.style, this.fallback});
  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream:
            FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder:
            (context, snapshot) => Text(
              snapshot.data?.data()?['deleted'] == true
                  ? tr(context, 'deletedUser')
                  : fallback ?? profileDisplayName(snapshot.data?.data()),
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      );
}
