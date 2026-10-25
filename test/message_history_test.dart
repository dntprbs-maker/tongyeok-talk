import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridgechat/message_history.dart';

class Meta extends Fake implements SnapshotMetadata {
  @override
  bool get hasPendingWrites => false;
}

// Test double only: lets the pagination tests run without a Firebase platform.
// ignore: subtype_of_sealed_class
class Row extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  final int number;
  final String status;
  Row(this.number, [this.status = 'done']);
  @override
  String get id => number.toString().padLeft(4, '0');
  @override
  bool get exists => true;
  @override
  SnapshotMetadata get metadata => Meta();
  @override
  Map<String, dynamic> data() => {
    'timestamp': Timestamp(100 + number ~/ 3, 0),
    'translationStatus': status,
    'originalText': id,
  };
}

class Source implements MessageSource {
  final rows = <MessageDoc>[for (var i = 1; i <= 120; i++) Row(i)];
  final head = StreamController<List<MessageDoc>>.broadcast();
  final updates = <String, StreamController<MessageDoc>>{};
  int subscriptions = 0, olderCalls = 0, gapCalls = 0;
  bool failOlder = false, failGap = false;
  Completer<List<MessageDoc>>? delayed;
  List<MessageDoc> get sorted =>
      rows.toList()..sort((a, b) => compareMessages(b, a));
  void emit() => head.add(sorted.take(50).toList());
  @override
  Stream<List<MessageDoc>> latest(int size) {
    subscriptions++;
    return head.stream;
  }

  @override
  Future<List<MessageDoc>> older(MessageDoc cursor, int size) async {
    olderCalls++;
    if (failOlder) {
      failOlder = false;
      throw StateError('offline');
    }
    if (delayed != null) return delayed!.future;
    return sorted
        .where((d) => compareMessages(d, cursor) < 0)
        .take(size)
        .toList();
  }

  @override
  Future<List<MessageDoc>> gap(
    MessageDoc cursor,
    MessageDoc end,
    int size,
  ) async {
    gapCalls++;
    if (failGap) {
      failGap = false;
      throw StateError('offline');
    }
    return sorted
        .where(
          (d) => compareMessages(d, cursor) < 0 && compareMessages(d, end) >= 0,
        )
        .take(size)
        .toList();
  }

  @override
  Stream<MessageDoc> changes(String id) =>
      updates
          .putIfAbsent(id, () => StreamController<MessageDoc>.broadcast())
          .stream;
  Future<void> close() async {
    await head.close();
    for (final s in updates.values) {
      await s.close();
    }
  }
}

Future<void> settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
    'partial cache head followed by server head still enables older pages',
    () async {
      final s = Source();
      final h = MessageHistory(s);
      s.head.add([]);
      await settle();
      expect(h.hasOlder, isFalse);
      s.emit();
      await settle();
      expect(h.hasOlder, isTrue);
      await h.loadOlder();
      expect(h.messages.length, 100);
      h.dispose();
      await s.close();
    },
  );
  test(
    '50/50/20 cursor pages preserve equal-timestamp messages without duplicates',
    () async {
      final s = Source();
      final history = MessageHistory(s);
      s.emit();
      await settle();
      expect(history.messages.length, 50);
      expect(history.hasOlder, isTrue);
      await history.loadOlder();
      expect(history.messages.length, 100);
      await history.loadOlder();
      expect(history.messages.length, 120);
      expect(history.hasOlder, isFalse);
      expect(history.messages.map((d) => d.id).toSet().length, 120);
      expect(history.messages.first.id, '0001');
      expect(history.messages.last.id, '0120');
      expect(s.subscriptions, 1);
      expect(s.olderCalls, 2);
      history.dispose();
      await s.close();
    },
  );
  test(
    'new live messages do not evict loaded history or change the older cursor',
    () async {
      final s = Source();
      final h = MessageHistory(s);
      s.emit();
      await settle();
      s.rows.add(Row(121));
      s.emit();
      await settle();
      expect(h.messages.length, 51);
      await h.loadOlder();
      await h.loadOlder();
      expect(h.messages.length, 121);
      expect(s.subscriptions, 1);
      h.dispose();
      await s.close();
    },
  );
  test(
    'burst larger than live window bridges the gap using bounded pages',
    () async {
      final s = Source();
      final h = MessageHistory(s);
      s.emit();
      await settle();
      s.rows.addAll([for (var i = 121; i <= 220; i++) Row(i)]);
      s.emit();
      await settle();
      expect(h.messages.length, 150);
      expect(s.gapCalls, 2);
      await h.loadOlder();
      await h.loadOlder();
      expect(h.messages.map((d) => d.id).toSet().length, 220);
      h.dispose();
      await s.close();
    },
  );
  test(
    'failed gap remains retryable and cannot silently lose messages',
    () async {
      final s = Source();
      final h = MessageHistory(s);
      s.emit();
      await settle();
      s.failGap = true;
      s.rows.addAll([for (var i = 121; i <= 220; i++) Row(i)]);
      s.emit();
      await settle();
      expect(h.pageError, isNotNull);
      h.retryGaps();
      await settle();
      expect(h.messages.length, 150);
      expect(h.pageError, isNull);
      h.dispose();
      await s.close();
    },
  );
  test('failed older page preserves loaded records and can retry', () async {
    final s = Source();
    final h = MessageHistory(s);
    s.emit();
    await settle();
    s.failOlder = true;
    await h.loadOlder();
    expect(h.messages.length, 50);
    expect(h.pageError, isNotNull);
    await h.loadOlder();
    expect(h.messages.length, 100);
    h.dispose();
    await s.close();
  });
  test(
    'unfinished historical translation stays live after leaving head window',
    () async {
      final s = Source();
      s.rows[0] = Row(1, 'pending');
      final h = MessageHistory(s);
      s.emit();
      await settle();
      await h.loadOlder();
      await h.loadOlder();
      expect(s.updates.keys, contains('0001'));
      s.updates['0001']!.add(Row(1));
      await settle();
      expect(h.messages.first.data()?['translationStatus'], 'done');
      h.dispose();
      await s.close();
    },
  );
  test(
    'completion after disposal does not notify or resurrect subscriptions',
    () async {
      final s = Source();
      final h = MessageHistory(s);
      s.emit();
      await settle();
      s.delayed = Completer();
      final pending = h.loadOlder();
      h.dispose();
      s.delayed!.complete([Row(1)]);
      await pending;
      await s.close();
    },
  );
}
