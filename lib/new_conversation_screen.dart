import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'chat_service.dart';
import 'chat_screen.dart';
import 'auth_service.dart';
import 'phone_identity.dart';
import 'app_language.dart';
import 'ui_errors.dart';

const _mobilePrefix = '010-';
const _emptyPhone = TextEditingValue(
  text: _mobilePrefix,
  selection: TextSelection.collapsed(offset: _mobilePrefix.length),
);

class _PhoneSearchFormatter extends TextInputFormatter {
  const _PhoneSearchFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final input = newValue.text;
    if (!newValue.composing.isCollapsed ||
        !RegExp(r'^[0-9-]*$').hasMatch(input)) {
      return newValue;
    }
    if (input.isEmpty || (oldValue.text == _mobilePrefix && input == '010')) {
      return _emptyPhone;
    }
    final suffix =
        input.startsWith(_mobilePrefix)
            ? input.substring(_mobilePrefix.length)
            : input;
    final digits = suffix.replaceAll('-', '');
    final String formatted;
    if (digits.length == 11 && digits.startsWith('010')) {
      formatted =
          '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7)}';
    } else if (digits.length <= 8) {
      if (digits.length <= 4) {
        formatted = '$_mobilePrefix$digits';
      } else {
        formatted =
            '$_mobilePrefix${digits.substring(0, 4)}-${digits.substring(4)}';
      }
    } else {
      return newValue;
    }
    if (formatted == input) return newValue;
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class NewConversationScreen extends StatefulWidget {
  const NewConversationScreen({super.key});
  @override
  State<NewConversationScreen> createState() => _NewConversationScreenState();
}

class _NewConversationScreenState extends State<NewConversationScreen> {
  final _phone = TextEditingController.fromValue(_emptyPhone);
  final List<Map<String, dynamic>> _selected = [];
  bool _group = false, _busy = false;
  String? _error;
  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  String _name(Map<String, dynamic> data) =>
      data['displayName'] as String? ??
      data['username'] as String? ??
      tr(context, 'unknownUser');
  Future<void> _find() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_group && _selected.length >= 10) {
        setState(() => _error = 'maxParticipants');
        return;
      }
      final user = await AuthService().findByPhone(
        PhoneIdentity.parseSearch(_phone.text),
      );
      if (!mounted) return;
      if (user == null) {
        setState(() => _error = 'userNotFound');
        return;
      }
      if (user['uid'] == FirebaseAuth.instance.currentUser!.uid) {
        setState(() => _error = 'selfChat');
        return;
      }
      if (_group) {
        if (_selected.any((u) => u['uid'] == user['uid'])) {
          setState(() => _error = 'alreadyAdded');
          return;
        }
        setState(() => _selected.add(user));
        _phone.value = _emptyPhone;
      } else {
        final cid = await ChatService().createOrGetConversation(
          FirebaseAuth.instance.currentUser!.uid,
          user['uid'] as String,
        );
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute<void>(
              builder:
                  (_) => ChatScreen(
                    conversationId: cid,
                    otherUserName: _name(user),
                  ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is FormatException ? 'phoneSearchHelp' : errorKey(e),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createGroup() async {
    if (_busy || _selected.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var name = _selected.map(_name).join(', ');
      if (name.length > 100) name = name.substring(0, 100);
      final room = await FirebaseFirestore.instance
          .collection('conversations')
          .add({
            'participants': [
              FirebaseAuth.instance.currentUser!.uid,
              ..._selected.map((u) => u['uid']),
            ],
            'isGroup': true,
            'groupName': name,
            'lastMessage': '',
            'timestamp': FieldValue.serverTimestamp(),
          });
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
            builder:
                (_) => ChatScreen(conversationId: room.id, otherUserName: name),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorKey(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'newChat'))),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr(context, 'groupChat')),
              value: _group,
              onChanged: _busy ? null : (v) => setState(() => _group = v),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('search-phone'),
              controller: _phone,
              autofocus: kIsWeb || defaultTargetPlatform != TargetPlatform.android,
              inputFormatters: const [_PhoneSearchFormatter()],
              enabled: !_busy,
              keyboardType: TextInputType.phone,
              onSubmitted: (_) => _find(),
              decoration: InputDecoration(
                labelText: tr(context, 'searchPhone'),
                hintText: '1234-5678',
                helperText: tr(context, 'phoneSearchHelp'),
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _find,
              child: Text(tr(context, _group ? 'addParticipant' : 'startChat')),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  tr(context, _error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_group) ...[
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    _selected
                        .map(
                          (u) => InputChip(
                            label: Text(_name(u)),
                            deleteButtonTooltipMessage: tr(
                              context,
                              'removeParticipant',
                            ),
                            onDeleted:
                                _busy
                                    ? null
                                    : () => setState(() => _selected.remove(u)),
                          ),
                        )
                        .toList(),
              ),
              if (_selected.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _createGroup,
                    icon: const Icon(Icons.group_add_outlined),
                    label: Text(tr(context, 'createGroup')),
                  ),
                ),
            ],
          ],
        ),
      ),
    ),
  );
}
