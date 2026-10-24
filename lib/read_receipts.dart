import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'app_language.dart';

final chatRouteObserver = RouteObserver<ModalRoute<void>>();

class ReadReceipts {
  static DocumentReference<Map<String, dynamic>> ref(String cid, String uid) =>
      FirebaseFirestore.instance
          .collection('conversations')
          .doc(cid)
          .collection('reads')
          .doc(uid);

  static Future<void> mark(String cid, String uid, Timestamp through) =>
      FirebaseFirestore.instance.runTransaction((tx) async {
        final receipt = ref(cid, uid);
        final old =
            (await tx.get(receipt)).data()?['readThrough'] as Timestamp?;
        if (old == null || old.compareTo(through) < 0) {
          tx.set(receipt, {'readThrough': through});
        }
      });
}

/// Counts incoming messages after the last message actually shown in this room.
/// The cursor is a committed message timestamp, never the time of opening a room.
class UnreadAvatar extends StatelessWidget {
  final String conversationId, uid;
  final bool group;
  const UnreadAvatar({
    super.key,
    required this.conversationId,
    required this.uid,
    required this.group,
  });
  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ReadReceipts.ref(conversationId, uid).snapshots(),
        builder: (context, receipt) {
          if (receipt.hasError) {
            return Icon(
              Icons.sync_problem,
              semanticLabel: tr(context, 'unreadError'),
            );
          }
          if (!receipt.hasData) {
            return CircleAvatar(
              child: Icon(group ? Icons.group_outlined : Icons.person_outline),
            );
          }
          Query<Map<String, dynamic>> pending = FirebaseFirestore.instance
              .collection('conversations')
              .doc(conversationId)
              .collection('messages')
              .orderBy('timestamp');
          final through = receipt.data?.data()?['readThrough'] as Timestamp?;
          if (through != null) pending = pending.startAfter([through]);
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: pending.snapshots(),
            builder: (context, messages) {
              if (messages.hasError) {
                return Icon(
                  Icons.sync_problem,
                  semanticLabel: tr(context, 'unreadError'),
                );
              }
              final count =
                  messages.data?.docs
                      .where((d) => d.data()['senderId'] != uid)
                      .length ??
                  0;
              return UnreadBadge(count: count, group: group);
            },
          );
        },
      );
}

class UnreadBadge extends StatelessWidget {
  final int count;
  final bool group;
  const UnreadBadge({super.key, required this.count, this.group = false});
  @override
  Widget build(BuildContext context) => Semantics(
    label: tr(context, 'unreadCount', {'count': '$count'}),
    child: Badge(
      isLabelVisible: count > 0,
      label: Text(count > 99 ? '99+' : '$count'),
      backgroundColor: const Color(0xFFD92C40),
      textColor: Colors.white,
      child: CircleAvatar(
        child: Icon(group ? Icons.group_outlined : Icons.person_outline),
      ),
    ),
  );
}
