import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'query_audit.dart';

typedef MessageDoc = DocumentSnapshot<Map<String, dynamic>>;

int compareMessages(MessageDoc a, MessageDoc b) {
  final x = a.data()?['timestamp'] as Timestamp?;
  final y = b.data()?['timestamp'] as Timestamp?;
  if (x == null && y != null) return 1; // local pending send stays at the end
  if (x != null && y == null) return -1;
  final time = x == null ? 0 : x.compareTo(y!);
  return time != 0 ? time : a.id.compareTo(b.id);
}

abstract class MessageSource {
  Stream<List<MessageDoc>> latest(int size);
  Future<List<MessageDoc>> older(MessageDoc cursor, int size);
  Future<List<MessageDoc>> gap(MessageDoc cursor, MessageDoc end, int size);
  Stream<MessageDoc> changes(String id);
}

class FirestoreMessageSource implements MessageSource {
  final CollectionReference<Map<String, dynamic>> messages;
  FirestoreMessageSource(String cid)
    : messages = FirebaseFirestore.instance
          .collection('conversations')
          .doc(cid)
          .collection('messages');
  Query<Map<String, dynamic>> get ordered => messages
      .orderBy('timestamp', descending: true)
      .orderBy(FieldPath.documentId, descending: true);
  @override
  Stream<List<MessageDoc>> latest(int size) {
    auditQuery('head_subscribe', {'limit': size});
    return ordered.limit(size).snapshots(includeMetadataChanges: true).map((s) {
      auditQuery('head_snapshot', {
        'documents': s.size,
        'changes': s.docChanges.length,
        'cache': s.metadata.isFromCache,
      });
      return s.docs;
    });
  }

  @override
  Future<List<MessageDoc>> older(MessageDoc cursor, int size) async {
    final s = await ordered.startAfterDocument(cursor).limit(size).get();
    auditQuery('older_page', {'limit': size, 'documents': s.size});
    return s.docs;
  }

  @override
  Future<List<MessageDoc>> gap(
    MessageDoc cursor,
    MessageDoc end,
    int size,
  ) async {
    final s =
        await ordered
            .startAfterDocument(cursor)
            .endAtDocument(end)
            .limit(size)
            .get();
    auditQuery('gap_page', {'limit': size, 'documents': s.size});
    return s.docs;
  }

  @override
  Stream<MessageDoc> changes(String id) => messages.doc(id).snapshots();
}

/// A bounded live head plus cursor pages. Eviction from the live limit is not
/// deletion: loaded history remains. Only unfinished old translations need
/// individual live subscriptions, because completed messages are immutable.
class MessageHistory extends ChangeNotifier {
  static const pageSize = 50;
  final MessageSource source;
  final Map<String, MessageDoc> _loaded = {};
  final Map<String, StreamSubscription<MessageDoc>> _unfinished = {};
  StreamSubscription<List<MessageDoc>>? _head;
  Set<String> _headIds = {};
  MessageDoc? _previousNewest;
  Future<void> _gapQueue = Future.value();
  final List<(MessageDoc, MessageDoc)> _failedGaps = [];
  bool ready = false, loadingOlder = false, hasOlder = false, _closed = false;
  bool _pagingStarted = false;
  Object? error, pageError;

  MessageHistory(this.source) {
    _head = source
        .latest(pageSize)
        .listen(
          _receive,
          onError: (Object e) {
            if (_closed) return;
            error = e;
            ready = true;
            notifyListeners();
          },
        );
  }
  List<MessageDoc> get messages =>
      _loaded.values.toList()..sort(compareMessages);

  void _receive(List<MessageDoc> docs) {
    if (_closed) return;
    final committed =
        docs
            .where(
              (d) =>
                  !d.metadata.hasPendingWrites &&
                  d.data()?['timestamp'] is Timestamp,
            )
            .toList();
    final oldNewest = _previousNewest;
    // An empty/partial local-cache snapshot can precede the server's full head.
    if (!_pagingStarted) hasOlder = docs.length >= pageSize;
    ready = true;
    error = null;
    _headIds = docs.map((d) => d.id).toSet();
    for (final d in docs) {
      _loaded[d.id] = d;
    }
    if (committed.isNotEmpty) {
      committed.sort(compareMessages);
      final newest = committed.last;
      final tail = committed.first;
      if (oldNewest != null &&
          committed.length >= pageSize &&
          compareMessages(tail, oldNewest) > 0) {
        _gapQueue = _gapQueue.then((_) => _fillGap(tail, oldNewest));
      }
      if (oldNewest == null || compareMessages(newest, oldNewest) > 0) {
        _previousNewest = newest;
      }
    }
    _watchUnfinished();
    notifyListeners();
  }

  Future<void> _fillGap(MessageDoc cursor, MessageDoc end) async {
    try {
      while (!_closed) {
        final rows = await source.gap(cursor, end, pageSize);
        if (_closed) return;
        for (final d in rows) {
          _loaded[d.id] = d;
        }
        _watchUnfinished();
        notifyListeners();
        if (rows.length < pageSize || compareMessages(rows.last, end) <= 0) {
          break;
        }
        cursor = rows.last;
      }
    } catch (e) {
      if (!_closed) {
        _failedGaps.add((cursor, end));
        pageError = e;
        notifyListeners();
      }
    }
  }

  void retryGaps() {
    final gaps = _failedGaps.toList();
    _failedGaps.clear();
    pageError = null;
    for (final (cursor, end) in gaps) {
      _gapQueue = _gapQueue.then((_) => _fillGap(cursor, end));
    }
  }

  Future<void> loadOlder() async {
    if (_closed || loadingOlder || !hasOlder || _loaded.isEmpty) return;
    final candidates = messages.where(
      (d) =>
          !d.metadata.hasPendingWrites && d.data()?['timestamp'] is Timestamp,
    );
    if (candidates.isEmpty) return;
    _pagingStarted = true;
    loadingOlder = true;
    pageError = null;
    notifyListeners();
    try {
      final rows = await source.older(candidates.first, pageSize);
      if (_closed) return;
      for (final d in rows) {
        _loaded[d.id] = d;
      }
      hasOlder = rows.length >= pageSize;
      _watchUnfinished();
    } catch (e) {
      if (!_closed) pageError = e;
    } finally {
      if (!_closed) {
        loadingOlder = false;
        notifyListeners();
      }
    }
  }

  void _watchUnfinished() {
    final needed =
        _loaded.values
            .where(
              (d) =>
                  !_headIds.contains(d.id) &&
                  d.data()?['translationStatus'] != 'done',
            )
            .map((d) => d.id)
            .toSet();
    for (final id in _unfinished.keys.toList()) {
      if (!needed.contains(id)) _unfinished.remove(id)?.cancel();
    }
    for (final id in needed) {
      if (_unfinished.containsKey(id)) continue;
      _unfinished[id] = source
          .changes(id)
          .listen(
            (d) {
              if (_closed || !d.exists) return;
              _loaded[id] = d;
              if (d.data()?['translationStatus'] == 'done') {
                _unfinished.remove(id)?.cancel();
              }
              notifyListeners();
            },
            onError: (Object e) {
              if (!_closed) {
                pageError = e;
                notifyListeners();
              }
            },
          );
    }
  }

  @override
  void dispose() {
    _closed = true;
    _head?.cancel();
    for (final sub in _unfinished.values) {
      sub.cancel();
    }
    super.dispose();
  }
}
