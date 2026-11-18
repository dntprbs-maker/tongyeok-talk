import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'app_language.dart';
import 'ui_errors.dart';
import 'profile_identity.dart';

/// Blocking is enforced by Firestore for both directions of direct messages.
class SafetyControls extends StatefulWidget {
  final String conversationId;
  const SafetyControls({super.key, required this.conversationId});
  @override
  State<SafetyControls> createState() => _SafetyControlsState();
}

class _SafetyControlsState extends State<SafetyControls> {
  final _details = TextEditingController();
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  final _db = FirebaseFirestore.instance;
  final _people = <String, String>{};
  String? _target, _error;
  String _reason = 'harassment';
  bool _loading = true, _busy = false, _blocked = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  DocumentReference<Map<String, dynamic>> get _block => _db
      .collection('users')
      .doc(_uid)
      .collection('blockedUsers')
      .doc(_target!);
  Future<void> _load() async {
    try {
      final room =
          (await _db
                  .collection('conversations')
                  .doc(widget.conversationId)
                  .get())
              .data();
      for (final person in List<String>.from(room?['participants'] ?? [])) {
        if (person == _uid) continue;
        final profile =
            (await _db.collection('users').doc(person).get()).data();
        _people[person] = profileDisplayName(profile);
      }
      if (_people.isNotEmpty) {
        _target = _people.keys.first;
        await _readBlock();
      }
    } catch (error) {
      _error = errorKey(error);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _readBlock() async {
    _blocked = (await _block.get()).data()?['blocked'] == true;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || _target == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      _error = errorKey(error);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'safetyTitle'))),
    body:
        _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(tr(context, 'blockScope')),
                const SizedBox(height: 16),
                if (_people.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: _target,
                    decoration: InputDecoration(
                      labelText: tr(context, 'safetyPerson'),
                    ),
                    items:
                        _people.entries
                            .map(
                              (p) => DropdownMenuItem(
                                value: p.key,
                                child: Text(p.value),
                              ),
                            )
                            .toList(),
                    onChanged:
                        _busy
                            ? null
                            : (value) => _run(() async {
                              _target = value;
                              await _readBlock();
                            }),
                  ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: Icon(_blocked ? Icons.lock_open : Icons.block),
                  label: Text(
                    tr(context, _blocked ? 'unblockUser' : 'blockUser'),
                  ),
                  onPressed:
                      _busy || _target == null
                          ? null
                          : () => _run(() async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder:
                                  (dialogContext) => AlertDialog(
                                    title: Text(
                                      tr(
                                        context,
                                        _blocked ? 'unblockUser' : 'blockUser',
                                      ),
                                    ),
                                    content: Text(
                                      tr(
                                        context,
                                        _blocked ? 'unblockHelp' : 'blockHelp',
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed:
                                            () => Navigator.pop(
                                              dialogContext,
                                              false,
                                            ),
                                        child: Text(tr(context, 'cancel')),
                                      ),
                                      FilledButton(
                                        onPressed:
                                            () => Navigator.pop(
                                              dialogContext,
                                              true,
                                            ),
                                        child: Text(
                                          tr(
                                            context,
                                            _blocked
                                                ? 'unblockUser'
                                                : 'blockUser',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                            );
                            if (confirmed != true) return;
                            await _block.set({
                              'blocked': !_blocked,
                              'updatedAt': FieldValue.serverTimestamp(),
                            });
                            await _readBlock();
                          }),
                ),
                const Divider(height: 32),
                DropdownButtonFormField<String>(
                  initialValue: _reason,
                  decoration: InputDecoration(
                    labelText: tr(context, 'reportReason'),
                  ),
                  items:
                      ['harassment', 'spam', 'inappropriate', 'other']
                          .map(
                            (r) => DropdownMenuItem(
                              value: r,
                              child: Text(tr(context, 'report_$r')),
                            ),
                          )
                          .toList(),
                  onChanged:
                      _busy
                          ? null
                          : (value) => setState(() => _reason = value!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _details,
                  maxLength: 500,
                  minLines: 2,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: tr(context, 'reportDetails'),
                  ),
                ),
                Text(tr(context, 'reportHelp')),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.flag_outlined),
                  label: Text(tr(context, 'reportUser')),
                  onPressed:
                      _busy || _target == null
                          ? null
                          : () => _run(() async {
                            await _db.collection('userReports').add({
                              'reportedBy': _uid,
                              'targetUid': _target,
                              'conversationId': widget.conversationId,
                              'reason': _reason,
                              'details': _details.text.trim(),
                              'createdAt': FieldValue.serverTimestamp(),
                            });
                            if (context.mounted) {
                              _details.clear();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(tr(context, 'reportSent')),
                                ),
                              );
                            }
                          }),
                ),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Text(
                    tr(context, _error!),
                    style: const TextStyle(color: Colors.red),
                  ),
              ],
            ),
  );
}
