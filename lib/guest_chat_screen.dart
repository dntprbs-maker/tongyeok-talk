import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_language.dart';
import 'chat_kind.dart';
import 'local_archive.dart';
import 'past_chats_screen.dart';
import 'message_bubble.dart';

const _guestBackendOverride = String.fromEnvironment('TONGYEOK_GUEST_BACKEND');
const _legacyGuestBackend =
    'https://asia-northeast3-tongyeok-talk-lab-20261024.cloudfunctions.net/rewardApi';
String get guestBackend =>
    _guestBackendOverride.isNotEmpty
        ? _guestBackendOverride
        : kIsWeb
        ? Uri.base.origin
        : _legacyGuestBackend;
Future<Map<String, dynamic>> guestApi(
  String action,
  Map<String, dynamic> body,
) async {
  final token = await FirebaseAuth.instance.currentUser!.getIdToken();
  final response = await http
      .post(
        Uri.parse('$guestBackend/guest-api/$action'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      )
      .timeout(const Duration(seconds: 25));
  final result = decodeGuestResponse(response.bodyBytes);
  if (response.statusCode != 200) {
    throw StateError(result['error'] as String? ?? 'unavailable');
  }
  return result;
}

Map<String, dynamic> decodeGuestResponse(List<int> bytes) =>
    jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

String guestError(Object error) =>
    error is StateError && error.message == 'no_credit'
        ? 'creditNoBalance'
        : error is StateError && error.message == 'mongolian_member_required'
        ? 'guestPayerRequired'
        : error is StateError && error.message == 'session_closed'
        ? 'guestEnded'
        : error is StateError && error.message == 'pilot_only'
        ? 'guestPilotOnly'
        : 'guestConnectionError';

class GuestInviteScreen extends StatefulWidget {
  const GuestInviteScreen({super.key});
  @override
  State<GuestInviteScreen> createState() => _GuestInviteScreenState();
}

class _GuestInviteScreenState extends State<GuestInviteScreen> {
  late final Future<Map<String, dynamic>> _invite = guestApi('create', {});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'guestInvite'))),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _invite,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(tr(context, guestError(snapshot.error!))),
            ),
          );
        }
        final invite = snapshot.data;
        if (invite == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final id = invite['id'] as String,
            link = '$guestBackend/guest?room=$id#invite=${invite['secret']}';
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              tr(context, 'guestInviteIntro'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(color: guestChatColor),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: QrImageView(
                  data: link,
                  size: 230,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(tr(context, 'guestQrHint'), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: guestChatColor),
              icon: const Icon(Icons.link),
              label: Text(tr(context, 'guestShare')),
              onPressed:
                  () => showModalBottomSheet<void>(
                    context: context,
                    builder:
                        (sheet) => SafeArea(
                          child: Wrap(
                            children: [
                              ListTile(
                                leading: const Icon(Icons.copy),
                                title: Text(tr(context, 'guestCopy')),
                                onTap: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: link),
                                  );
                                  if (sheet.mounted) Navigator.pop(sheet);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          tr(context, 'guestCopied'),
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.sms_outlined),
                                title: Text(tr(context, 'guestSms')),
                                onTap: () async {
                                  Navigator.pop(sheet);
                                  final ok = await launchUrl(
                                    Uri(
                                      scheme: 'sms',
                                      query:
                                          'body=${Uri.encodeComponent(link)}',
                                    ),
                                    mode: LaunchMode.externalApplication,
                                  );
                                  if (!ok && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          tr(context, 'guestCopyFallback'),
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                  ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.search),
              label: Text(tr(context, 'findPeople')),
              onPressed: () => Navigator.pushNamed(context, '/newConversation'),
            ),
            const SizedBox(height: 16),
            _GuestNotice(text: tr(context, 'guestMemberNotice')),
            Text(
              tr(context, 'guestInviteExpiry'),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.chat_outlined),
              label: Text(tr(context, 'guestOpenChat')),
              onPressed:
                  () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => GuestMemberChat(id: id),
                    ),
                  ),
            ),
          ],
        );
      },
    ),
  );
}

class GuestMemberChat extends StatefulWidget {
  final String id;
  const GuestMemberChat({super.key, required this.id});
  @override
  State<GuestMemberChat> createState() => _GuestMemberChatState();
}

class _GuestMemberChatState extends State<GuestMemberChat> {
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  final _text = TextEditingController();
  final _scroll = ScrollController();
  Timer? _timer;
  Map<String, dynamic>? _room;
  String? _error, _lastSaved, _sendId, _sendText;
  bool _sending = false, _closing = false, _polling = false;
  @override
  void initState() {
    super.initState();
    _poll();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String get _name =>
      (_room?['guestName'] as String?)?.isNotEmpty == true
          ? _room!['guestName'] as String
          : AppLanguage.instance.text('guestWaiting');
  Future<void> _poll() async {
    if (_polling || !mounted) return;
    _polling = true;
    _timer?.cancel();
    try {
      final room = await guestApi('read', {'id': widget.id});
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != _uid) return;
      final changed = jsonEncode(room['messages']);
      if (changed != _lastSaved) {
        final rows =
            (room['messages'] as List)
                .map(
                  (m) => <String, dynamic>{
                    ...Map<String, dynamic>.from(m as Map),
                    'mine': m['sender'] == 'member',
                  },
                )
                .toList();
        if (rows.isNotEmpty) {
          await LocalArchive.instance.save(
            _uid,
            'guest:${widget.id}',
            room['guestName'] as String? ?? '',
            true,
            rows,
          );
        }
        if (room['status'] == 'ended' &&
            rows.isNotEmpty &&
            rows.every((m) => ['done', 'failed'].contains(m['status']))) {
          // Ack only after the durable transaction succeeds. Subsequent empty
          // server snapshots never overwrite the device's saved messages.
          await guestApi('ack', {
            'id': widget.id,
            'ids': rows.map((m) => m['id']).toList(),
          });
        }
        _lastSaved = changed;
      }
      if (!mounted) return;
      final nearBottom =
          !_scroll.hasClients || _scroll.position.extentAfter < 100;
      setState(() {
        _room = room;
        _error = null;
      });
      if (nearBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = guestError(e));
    }
    _polling = false;
    if (mounted) _timer = Timer(const Duration(seconds: 4), _poll);
  }

  Future<void> _send() async {
    if (_sending || _text.text.trim().isEmpty || _text.text.runes.length > 50) {
      return;
    }
    final value = _text.text;
    if (_sendText != value) {
      _sendText = value;
      _sendId =
          List.generate(
            16,
            (_) =>
                Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
          ).join();
    }
    setState(() => _sending = true);
    try {
      await guestApi('send', {
        'id': widget.id,
        'text': value,
        'messageId': _sendId,
      });
      _sendId = null;
      _sendText = null;
      _text.clear();
      _timer?.cancel();
      await _poll();
    } catch (e) {
      if (mounted) setState(() => _error = guestError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _end() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(tr(context, 'guestEnd')),
            content: Text(tr(context, 'guestEndConfirm')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr(context, 'cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(tr(context, 'guestEnd')),
              ),
            ],
          ),
    );
    if (accepted != true || !mounted) return;
    setState(() => _closing = true);
    try {
      await guestApi('end', {'id': widget.id});
      _timer?.cancel();
      await _poll();
    } catch (e) {
      if (mounted) setState(() => _error = guestError(e));
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ended = _room?['status'] == 'ended',
        active = _room?['status'] == 'active';
    final rows =
        (_room?['messages'] as List? ?? [])
            .map(
              (m) => <String, dynamic>{
                ...Map<String, dynamic>.from(m as Map),
                'mine': m['sender'] == 'member',
              },
            )
            .toList();
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(_name), const ChatKindBadge(guest: true)],
        ),
        actions: [
          TextButton(
            onPressed: ended || _closing ? null : _end,
            child: Text(
              tr(context, 'guestEnd'),
              style: const TextStyle(color: guestChatColor),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _GuestNotice(text: tr(context, 'guestMemberNotice')),
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    tr(context, 'currentChats'),
                    style: const TextStyle(
                      color: guestChatColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder:
                            (_) => SavedChatScreen(
                              room: 'guest:${widget.id}',
                              name: _name,
                              guest: true,
                            ),
                      ),
                    ),
                child: Text(tr(context, 'pastChats')),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                tr(context, _error!),
                style: const TextStyle(color: Colors.red),
              ),
            ),
          if (_room == null) const LinearProgressIndicator(),
          Expanded(
            child:
                ended
                    ? Center(child: Text(tr(context, 'guestEnded')))
                    : !active
                    ? Center(child: Text(tr(context, 'guestWaiting')))
                    : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: rows.length,
                      itemBuilder: (context, i) {
                        final message = rows[i];
                        final source = message['source'] == 'mn' ? 'mn' : 'ko';
                        return MessageBubble(
                          key: ValueKey(message['id']),
                          senderId: message['sender'] as String,
                          currentUserId: 'member',
                          originalText: message['original'] as String,
                          translatedText:
                              message['translation'] as String? ?? '',
                          sourceLang: source,
                          targetLang: source == 'ko' ? 'mn' : 'ko',
                          translationStatus: message['status'] as String,
                          timestamp: DateTime.fromMillisecondsSinceEpoch(
                            (message['time'] as num).toInt(),
                          ),
                        );
                      },
                    ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              tr(context, 'localSavedHint'),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
          if (active)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _text,
                        onChanged: (_) => setState(() {}),
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: tr(context, 'message'),
                          counterText: '${_text.text.runes.length}/50',
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed:
                          _sending ||
                                  _text.text.trim().isEmpty ||
                                  _text.text.runes.length > 50
                              ? null
                              : _send,
                      icon: const Icon(Icons.send, color: guestChatColor),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GuestNotice extends StatelessWidget {
  final String text;
  const _GuestNotice({required this.text});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.all(12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: guestChatColor.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, color: guestChatColor),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: guestChatColor),
          ),
        ),
      ],
    ),
  );
}
