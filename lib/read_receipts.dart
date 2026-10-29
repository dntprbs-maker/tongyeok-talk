import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'app_language.dart';
import 'query_audit.dart';

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

/// Server-side aggregation returns a number, never message bodies. Refreshes
/// only when the room's message revision or this user's read cursor changes.
class UnreadAvatar extends StatefulWidget {
  final String conversationId, uid;
  final bool group;
  final String? displayName;
  final Timestamp? messageRevision;
  final Stream<Timestamp?>? receiptStream;
  final Future<int> Function(Timestamp?)? countLoader;
  const UnreadAvatar({
    super.key,
    required this.conversationId,
    required this.uid,
    required this.group,
    this.displayName,
    this.messageRevision,
    this.receiptStream,
    this.countLoader,
  });
  @override
  State<UnreadAvatar> createState() => _UnreadAvatarState();
}

class _UnreadAvatarState extends State<UnreadAvatar>
    with WidgetsBindingObserver {
  StreamSubscription<Timestamp?>? _subscription;
  Timer? _debounce;
  Timestamp? _through;
  bool _hasReceipt = false, _error = false;
  int _count = 0, _generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscribe();
  }

  void _subscribe() {
    final stream =
        widget.receiptStream ??
        ReadReceipts.ref(
          widget.conversationId,
          widget.uid,
        ).snapshots().map((s) => s.data()?['readThrough'] as Timestamp?);
    _subscription = stream.listen(
      (through) {
        if (_hasReceipt && through == _through) return;
        _hasReceipt = true;
        _through = through;
        _refresh();
      },
      onError: (_) {
        if (mounted) setState(() => _error = true);
      },
    );
  }

  @override
  void didUpdateWidget(covariant UnreadAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId ||
        oldWidget.uid != widget.uid ||
        oldWidget.receiptStream != widget.receiptStream) {
      _generation++;
      _debounce?.cancel();
      _subscription?.cancel();
      _hasReceipt = false;
      _through = null;
      _count = 0;
      _error = false;
      _subscribe();
    } else if (oldWidget.messageRevision != widget.messageRevision) {
      _refresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() {
    if (!_hasReceipt) return;
    final generation = ++_generation;
    final through = _through;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 100), () async {
      try {
        final count = await (widget.countLoader ?? _loadCount)(through);
        if (mounted && generation == _generation) {
          setState(() {
            _count = count;
            _error = false;
          });
        }
      } catch (_) {
        if (mounted && generation == _generation) setState(() => _error = true);
      }
    });
  }

  Future<int> _loadCount(Timestamp? through) async {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.conversationId)
        .collection('messages')
        .where('senderId', isNotEqualTo: widget.uid);
    if (through != null) {
      query = query.where('timestamp', isGreaterThan: through);
    }
    query = query.orderBy('senderId').orderBy('timestamp');
    auditQuery('unread_aggregate_request');
    final result = await query.count().get();
    auditQuery('unread_aggregate_result', {'count': result.count});
    return result.count ?? 0;
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    _subscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _error
          ? Tooltip(
            message: tr(context, 'unreadError'),
            child: InkWell(
              onTap: _refresh,
              child: Icon(
                Icons.sync_problem,
                semanticLabel: tr(context, 'unreadError'),
              ),
            ),
          )
          : UnreadBadge(
            count: _count,
            group: widget.group,
            displayName: widget.displayName,
          );
}

class UnreadBadge extends StatelessWidget {
  final int count;
  final bool group;
  final String? displayName;
  const UnreadBadge({
    super.key,
    required this.count,
    this.group = false,
    this.displayName,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    label: tr(context, 'unreadCount', {'count': '$count'}),
    child: Badge(
      isLabelVisible: count > 0,
      label: Text(count > 99 ? '99+' : '$count'),
      backgroundColor: const Color(0xFFD92C40),
      textColor: Colors.white,
      child: CircleAvatar(
        backgroundColor:
            group ? const Color(0xFFECE8FF) : const Color(0xFFE2EFFF),
        foregroundColor: const Color(0xFF3346B8),
        child:
            !group && displayName != null && displayName!.isNotEmpty
                ? Text(
                  displayName!.characters.first,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                )
                : Icon(group ? Icons.group_outlined : Icons.person_outline),
      ),
    ),
  );
}
