import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_language.dart';
import 'ui_errors.dart';

class GroupSettingsScreen extends StatefulWidget {
  final String conversationId;
  const GroupSettingsScreen({super.key, required this.conversationId});
  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  final _name = TextEditingController();
  final _users = <String>[];
  bool _loading = true, _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data =
          (await FirebaseFirestore.instance
                  .collection('conversations')
                  .doc(widget.conversationId)
                  .get())
              .data()!;
      _name.text = data['groupName'] as String? ?? '';
      for (final uid in data['participants'] as List) {
        final p =
            (await FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid as String)
                    .get())
                .data();
        _users.add(
          p?['displayName'] as String? ??
              p?['username'] as String? ??
              AppLanguage.instance.text('unknownUser'),
        );
      }
    } catch (e) {
      _error = errorKey(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _name.text.trim().length > 100) {
      setState(() => _error = 'groupNameInvalid');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId)
          .update({'groupName': _name.text.trim()});
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(tr(context, 'saved'))));
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorKey(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'groupSettings'))),
    body:
        _loading
            ? const Center(child: CircularProgressIndicator())
            : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    TextField(
                      controller: _name,
                      maxLength: 100,
                      decoration: InputDecoration(
                        labelText: tr(context, 'groupName'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: Text(tr(context, 'save')),
                    ),
                    if (_error != null)
                      Text(
                        tr(context, _error!),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    const SizedBox(height: 28),
                    Text(
                      tr(context, 'participants'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    ..._users.map(
                      (name) => ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text(name),
                      ),
                    ),
                  ],
                ),
              ),
            ),
  );
}
