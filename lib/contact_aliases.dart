import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'app_language.dart';

String? directChatPeer(Map<String, dynamic> room, String uid) {
  final participants = room['participants'];
  if (room['isGroup'] == true ||
      participants is! List ||
      participants.length != 2) {
    return null;
  }
  if (!participants.contains(uid)) return null;
  final peer = participants.first == uid ? participants.last : participants.first;
  return peer is String && peer.isNotEmpty && peer != uid ? peer : null;
}

class ContactAliases {
  ContactAliases(String owner)
    : _entries = FirebaseFirestore.instance
          .collection('users')
          .doc(owner)
          .collection('contactAliases');

  final CollectionReference<Map<String, dynamic>> _entries;

  Stream<Map<String, String>> watchAll() => _entries.snapshots().map(
    (snapshot) => {
      for (final document in snapshot.docs)
        if (document.data()['alias'] case final String alias)
          document.id: alias,
    },
  );

  Stream<String?> watch(String peer) => _entries
      .doc(peer)
      .snapshots()
      .map((snapshot) => snapshot.data()?['alias'] as String?);

  Future<void> update(String peer, String? alias) =>
      alias == null
          ? _entries.doc(peer).delete()
          : _entries.doc(peer).set({'alias': alias});
}

class ContactAliasDialog extends StatefulWidget {
  const ContactAliasDialog({
    super.key,
    required this.original,
    required this.alias,
    required this.onSave,
  });

  final String original;
  final String? alias;
  final Future<void> Function(String?) onSave;

  @override
  State<ContactAliasDialog> createState() => _ContactAliasDialogState();
}

class _ContactAliasDialogState extends State<ContactAliasDialog> {
  late final _controller = TextEditingController(text: widget.alias);
  bool _busy = false;
  String? _error;

  Future<void> _save({bool remove = false}) async {
    if (_busy) return;
    final value = _controller.text.trim();
    if (!remove &&
        (value.isEmpty ||
            value.runes.length > 60 ||
            value.contains(RegExp(r'[\r\n]')))) {
      setState(() => _error = 'contactAliasInvalid');
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await widget.onSave(remove ? null : value);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'contactAliasSaveError';
          _busy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(tr(context, 'contactAliasEdit')),
      scrollable: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tr(context, 'contactAliasOriginal', {'name': widget.original})),
          const SizedBox(height: 6),
          Text(tr(context, 'contactAliasPrivate')),
          const SizedBox(height: 12),
          TextField(
            autofocus: true,
            enabled: !_busy,
            controller: _controller,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: tr(context, 'contactAlias'),
              errorText: _error == null ? null : tr(context, _error!),
            ),
          ),
        ],
      ),
      actions: [
        if (widget.alias != null)
          TextButton(
            onPressed: _busy ? null : () => _save(remove: true),
            child: Text(tr(context, 'contactAliasRemove')),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(tr(context, 'cancel')),
        ),
        FilledButton(
          onPressed: _busy ? null : () => _save(),
          child: Text(tr(context, 'contactAliasSave')),
        ),
      ],
    ),
  );
}
