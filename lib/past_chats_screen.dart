import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'local_archive.dart';
import 'app_language.dart';
import 'chat_kind.dart';

class PastChats extends StatefulWidget {
  const PastChats({super.key});
  @override
  State<PastChats> createState() => _PastChatsState();
}

class _PastChatsState extends State<PastChats> {
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  late Stream<List<Map<String, dynamic>>> _rooms = LocalArchive.instance.rooms(
    _uid,
  );
  String _search = '';
  Timer? _debounce;
  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Text(tr(context, 'localHistoryHint')),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          decoration: InputDecoration(
            hintText: tr(context, 'archiveSearch'),
            prefixIcon: const Icon(Icons.search),
          ),
          onChanged: (value) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 250), () {
              if (mounted) {
                setState(() {
                  _search = value;
                  _rooms = LocalArchive.instance.rooms(_uid, search: value);
                });
              }
            });
          },
        ),
      ),
      Expanded(
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _rooms,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text(tr(context, 'archiveError')));
            }
            final rows = snapshot.data;
            if (rows == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (rows.isEmpty) {
              return Center(
                child: Text(
                  tr(
                    context,
                    _search.trim().isEmpty
                        ? 'noLocalHistory'
                        : 'archiveNoSearch',
                  ),
                ),
              );
            }
            return ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final row = rows[i], guest = row['guest'] == true;
                return ListTile(
                  leading: Icon(
                    Icons.history,
                    color: guest ? guestChatColor : memberChatColor,
                  ),
                  title: Text(row['name'] as String),
                  subtitle: ChatKindBadge(guest: guest),
                  trailing: Text(
                    DateFormat('MM.dd HH:mm').format(
                      DateTime.fromMillisecondsSinceEpoch(
                        (row['time'] as num).toInt(),
                      ),
                    ),
                  ),
                  onTap:
                      () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder:
                              (_) => SavedChatScreen(
                                room: row['room'] as String,
                                name: row['name'] as String,
                                guest: guest,
                              ),
                        ),
                      ),
                );
              },
            );
          },
        ),
      ),
    ],
  );
}

class SavedChatScreen extends StatelessWidget {
  final String room, name;
  final bool guest;
  const SavedChatScreen({
    super.key,
    required this.room,
    required this.name,
    required this.guest,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Text(name), ChatKindBadge(guest: guest)],
      ),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(tr(context, 'savedReadOnly')),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: LocalArchive.instance.messages(
              FirebaseAuth.instance.currentUser!.uid,
              room,
            ),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text(tr(context, 'archiveError')));
              }
              final rows = snapshot.data ?? [];
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                itemBuilder:
                    (context, i) => ArchiveBubble(
                      message: rows[i],
                      color: guest ? guestChatColor : memberChatColor,
                    ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class ArchiveBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final Color color;
  const ArchiveBubble({super.key, required this.message, required this.color});
  @override
  Widget build(BuildContext context) {
    final mine = message['mine'] == true,
        original = message['original'] as String? ?? '',
        translation = message['translation'] as String? ?? '';
    final originalFirst = message['source'] == AppLanguage.instance.code;
    final main = originalFirst || translation.isEmpty ? original : translation;
    final other =
        translation.isEmpty
            ? ''
            : originalFirst
            ? translation
            : original;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        margin: const EdgeInsets.symmetric(vertical: 7),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: mine ? color : const Color(0xFFF1F3F5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              main,
              style: TextStyle(
                fontSize: 16,
                color: mine ? Colors.white : Colors.black87,
              ),
            ),
            if (other.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  other,
                  style: TextStyle(
                    fontSize: 12,
                    color: mine ? Colors.white70 : Colors.black54,
                  ),
                ),
              ),
            if (message['status'] == 'pending' ||
                message['status'] == 'processing')
              Text(
                tr(context, 'translationPending'),
                style: TextStyle(
                  fontSize: 11,
                  color: mine ? Colors.white70 : Colors.black54,
                ),
              ),
            if (message['status'] == 'failed')
              Text(
                tr(context, 'translationFailed'),
                style: TextStyle(
                  fontSize: 11,
                  color: mine ? Colors.white70 : Colors.black54,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
