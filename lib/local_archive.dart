import 'dart:convert';
import 'package:sembast/sembast.dart';
import 'local_archive_open.dart';

// A separate durable store, never an evictable Firestore cache. Every operation
// scopes both its room and message keys to the authenticated member's UID.
class LocalArchive {
  static final instance = LocalArchive(openArchiveDatabase);
  final Future<Database> Function() open;
  Future<Database>? _database;
  final _rooms = stringMapStoreFactory.store('rooms');
  final _messages = stringMapStoreFactory.store('messages');
  LocalArchive(this.open);
  Future<Database> get database => _database ??= _openAndRepair();

  Future<Database> _openAndRepair() async {
    final db = await open();
    final marker = StoreRef<String, int>('meta').record('guestTextVersion');
    await db.transaction((txn) async {
      if (await marker.get(txn) == 2) return;
      // Trial builds decoded guest responses as Latin-1 before persisting.
      // Restore their original UTF-8 bytes, leaving non-guest data untouched.
      for (final room in await _rooms.find(
        txn,
        finder: Finder(filter: Filter.equals('guest', true)),
      )) {
        await _rooms.record(room.key).update(txn, {
          'name': _repairText(room.value['name']),
        });
        final filter = Filter.and([
          Filter.equals('uid', room.value['uid']),
          Filter.equals('room', room.value['room']),
        ]);
        for (final message in await _messages.find(
          txn,
          finder: Finder(filter: filter),
        )) {
          await _messages.record(message.key).update(txn, {
            'original': _repairText(message.value['original']),
            'translation': _repairText(message.value['translation']),
          });
        }
      }
      await marker.put(txn, 2);
    });
    return db;
  }

  String _repairText(Object? value) {
    final text = value as String? ?? '';
    try {
      return utf8.decode(latin1.encode(text));
    } on FormatException {
      return text;
    } on ArgumentError {
      return text;
    }
  }

  Future<void> removeAccount(String uid) async {
    final db = await database;
    await db.transaction((txn) async {
      final owned = Finder(filter: Filter.equals('uid', uid));
      await _messages.delete(txn, finder: owned);
      await _rooms.delete(txn, finder: owned);
    });
  }

  String key(String uid, String room) => '$uid/$room';
  Future<void> save(
    String uid,
    String room,
    String name,
    bool guest,
    List<Map<String, dynamic>> messages,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      final previous = await _rooms.record(key(uid, room)).get(txn);
      var latest = (previous?['time'] as num?)?.toInt() ?? 0;
      for (final message in messages) {
        final id = message['id'] as String;
        final old = await _messages.record('${key(uid, room)}/$id').get(txn);
        final data = <String, Object?>{...message};
        if ((data['translation'] as String? ?? '').isEmpty && old != null) {
          data['translation'] = old['translation'] ?? '';
          if (old['status'] == 'done') data['status'] = 'done';
        }
        await _messages.record('${key(uid, room)}/$id').put(txn, {
          ...data,
          'uid': uid,
          'room': room,
        });
        final time = (message['time'] as num?)?.toInt() ?? 0;
        if (time > latest) latest = time;
      }
      await _rooms.record(key(uid, room)).put(txn, {
        'uid': uid,
        'room': room,
        'name': name,
        'guest': guest,
        'time': latest,
      });
    });
  }

  Future<void> translation(
    String uid,
    String room,
    String id,
    String text,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      final ref = _messages.record('${key(uid, room)}/$id');
      if (await ref.exists(txn)) await ref.update(txn, {'translation': text});
    });
  }

  Stream<List<Map<String, dynamic>>> rooms(
    String uid, {
    String search = '',
  }) async* {
    final db = await database;
    final query = search.trim().toLowerCase();
    yield* _rooms
        .query(
          finder: Finder(
            filter: Filter.equals('uid', uid),
            sortOrders: [SortOrder('time', false)],
          ),
        )
        .onSnapshots(db)
        .asyncMap((rows) async {
          final all = rows.map((r) => r.value).toList();
          if (query.isEmpty) return all;
          final messages = await _messages.find(
            db,
            finder: Finder(filter: Filter.equals('uid', uid)),
          );
          final matchingRooms =
              messages
                  .where(
                    (m) => ['original', 'translation'].any(
                      (k) => (m.value[k] as String? ?? '')
                          .toLowerCase()
                          .contains(query),
                    ),
                  )
                  .map((m) => m.value['room'])
                  .toSet();
          return all
              .where(
                (r) =>
                    matchingRooms.contains(r['room']) ||
                    (r['name'] as String).toLowerCase().contains(query),
              )
              .toList();
        });
  }

  Stream<List<Map<String, dynamic>>> messages(String uid, String room) async* {
    final db = await database;
    yield* _messages
        .query(
          finder: Finder(
            filter: Filter.and([
              Filter.equals('uid', uid),
              Filter.equals('room', room),
            ]),
            sortOrders: [SortOrder('time'), SortOrder('id')],
          ),
        )
        .onSnapshots(db)
        .map((rows) => rows.map((r) => r.value).toList());
  }
}
