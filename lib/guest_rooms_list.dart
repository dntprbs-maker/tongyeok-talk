import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'guest_chat_screen.dart';
import 'app_language.dart';
import 'chat_kind.dart';
import 'local_archive.dart';

Future<void> syncGuestArchive(String id) async {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  final room = await guestApi('read', {'id': id});
  if (FirebaseAuth.instance.currentUser?.uid != uid) return;
  final rows =
      (room['messages'] as List)
          .map(
            (m) => <String, dynamic>{
              ...Map<String, dynamic>.from(m as Map),
              'mine': m['sender'] == 'member',
            },
          )
          .toList();
  if (rows.isEmpty) return;
  final name =
      (room['guestName'] as String? ?? '').isNotEmpty
          ? room['guestName'] as String
          : AppLanguage.instance.text('guestBadge');
  await LocalArchive.instance.save(uid, 'guest:$id', name, true, rows);
  if (room['status'] == 'ended' &&
      rows.every((m) => ['done', 'failed'].contains(m['status']))) {
    await guestApi('ack', {'id': id, 'ids': rows.map((m) => m['id']).toList()});
  }
}

class GuestRoomsList extends StatefulWidget {
  const GuestRoomsList({super.key});
  @override
  State<GuestRoomsList> createState() => _GuestRoomsListState();
}

class _GuestRoomsListState extends State<GuestRoomsList> {
  late final _rooms =
      FirebaseFirestore.instance
          .collection('guestRooms')
          .where('owner', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
          .snapshots();
  final _syncing = <String>{};
  final _savedRevision = <String, String>{};
  final _latestRevision = <String, String>{};
  String? _error;
  void _sync(String id, String revision) {
    _latestRevision[id] = revision;
    if (_syncing.contains(id) || _savedRevision[id] == revision) return;
    _syncing.add(id);
    syncGuestArchive(id)
        .then((_) {
          _savedRevision[id] = revision;
          if (mounted && _error != null) setState(() => _error = null);
        })
        .catchError((Object _) {
          if (mounted && _error == null) {
            setState(() => _error = 'archiveError');
          }
        })
        .whenComplete(() {
          _syncing.remove(id);
          final next = _latestRevision[id];
          if (mounted && next != null && next != revision) {
            _sync(id, next);
          }
        });
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _rooms,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Text(tr(context, 'guestConnectionError')),
            );
          }
          final docs = snapshot.data?.docs ?? [];
          for (final doc in docs) {
            final d = doc.data();
            if (d['archivedAt'] == null && (d['count'] as int? ?? 0) > 0) {
              _sync(doc.id, '${d['updatedAt']}');
            }
          }
          final rooms =
              docs
                  .where(
                    (d) =>
                        ['waiting', 'active'].contains(d.data()['status']) &&
                        (d.data()['expiresAt'] as Timestamp).toDate().isAfter(
                          DateTime.now(),
                        ),
                  )
                  .toList()
                ..sort(
                  (a, b) => (b.data()['updatedAt'] as Timestamp).compareTo(
                    a.data()['updatedAt'] as Timestamp,
                  ),
                );
          return Column(
            children: [
              if (_error != null)
                Text(
                  tr(context, _error!),
                  style: const TextStyle(color: Colors.red),
                ),
              for (final doc in rooms)
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE2F2ED),
                    child: Icon(Icons.person_outline, color: guestChatColor),
                  ),
                  title: Text(
                    (doc.data()['guestName'] as String).isNotEmpty
                        ? doc.data()['guestName'] as String
                        : tr(context, 'guestWaiting'),
                  ),
                  subtitle: const ChatKindBadge(guest: true),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: guestChatColor,
                  ),
                  onTap:
                      () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => GuestMemberChat(id: doc.id),
                        ),
                      ),
                ),
            ],
          );
        },
      );
}
