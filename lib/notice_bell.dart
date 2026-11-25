import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'app_language.dart';
import 'read_receipts.dart';

class NoticeBell extends StatelessWidget {
  const NoticeBell({super.key, required this.hasUnread, required this.onOpen});

  final bool hasUnread;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tr(context, hasUnread ? 'noticesUnread' : 'noticesTitle'),
    icon: Badge(
      isLabelVisible: hasUnread,
      smallSize: 7,
      backgroundColor: const Color(0xFFD92C40),
      child: const Icon(Icons.notifications_outlined),
    ),
    onPressed: onOpen,
  );
}

class ConversationNoticeBell extends StatefulWidget {
  const ConversationNoticeBell({
    super.key,
    required this.uid,
    required this.revisions,
    required this.onOpen,
  });

  final String uid;
  final Map<String, Timestamp?> revisions;
  final VoidCallback onOpen;

  @override
  State<ConversationNoticeBell> createState() => _ConversationNoticeBellState();
}

class _NoticeRoom {
  _NoticeRoom(this.revision);

  Timestamp? revision, cursor;
  late final StreamSubscription<Timestamp?> subscription;
  bool ready = false, unread = false;
  int generation = 0;
}

class _ConversationNoticeBellState extends State<ConversationNoticeBell> {
  final _rooms = <String, _NoticeRoom>{};

  @override
  void initState() {
    super.initState();
    _syncRooms();
  }

  @override
  void didUpdateWidget(ConversationNoticeBell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) _clearRooms();
    _syncRooms();
  }

  void _syncRooms() {
    for (final id in _rooms.keys.toList()) {
      if (!widget.revisions.containsKey(id)) {
        _rooms.remove(id)!.subscription.cancel();
      }
    }
    for (final entry in widget.revisions.entries) {
      final id = entry.key;
      final existing = _rooms[id];
      if (existing != null) {
        if (existing.revision != entry.value) {
          existing.revision = entry.value;
          _refresh(id, existing);
        }
        continue;
      }
      final room = _rooms[id] = _NoticeRoom(entry.value);
      room.subscription = ReadReceipts.ref(id, widget.uid)
          .snapshots()
          .map((snapshot) => snapshot.data()?['readThrough'] as Timestamp?)
          .listen(
            (cursor) {
              if (room.ready && room.cursor == cursor) return;
              if (room.cursor != cursor && room.unread && mounted) {
                setState(() => room.unread = false);
              }
              room.cursor = cursor;
              room.ready = true;
              _refresh(id, room);
            },
            onError: (Object error) {
              if (!mounted || _rooms[id] != room) return;
              room.ready = false;
              room.generation++;
              setState(() => room.unread = false);
            },
          );
    }
  }

  Future<void> _refresh(String id, _NoticeRoom room) async {
    if (!room.ready) return;
    final revision = room.revision;
    if (revision == null || (room.cursor?.compareTo(revision) ?? -1) >= 0) {
      room.generation++;
      room.unread = false;
      return;
    }
    final generation = ++room.generation;
    var unread = false;
    try {
      unread =
          await ReadReceipts.unreadCount(
            id,
            widget.uid,
            room.cursor,
            firstOnly: true,
          ) >
          0;
    } catch (_) {
      // An unconfirmed result must not show an unread indicator.
    }
    if (mounted &&
        _rooms[id] == room &&
        generation == room.generation &&
        room.unread != unread) {
      setState(() => room.unread = unread);
    }
  }

  void _clearRooms() {
    for (final room in _rooms.values) {
      room.subscription.cancel();
    }
    _rooms.clear();
  }

  @override
  void dispose() {
    _clearRooms();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NoticeBell(
    hasUnread: _rooms.values.any((room) => room.unread),
    onOpen: widget.onOpen,
  );
}
