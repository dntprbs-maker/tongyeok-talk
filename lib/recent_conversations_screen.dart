import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_screen.dart';
import 'app_language.dart';
import 'ui_errors.dart';

class RecentConversationsScreen extends StatelessWidget {
  RecentConversationsScreen({super.key});
  final currentUser = FirebaseAuth.instance.currentUser!;
  Future<String> _displayName(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final group = data['groupName'] as String?;
    if (group != null && group.trim().isNotEmpty) return group;
    final names = <String>[];
    for (final uid in (data['participants'] as List).where(
      (id) => id != currentUser.uid,
    )) {
      final profile =
          (await FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid as String)
                  .get())
              .data();
      names.add(
        profile?['displayName'] as String? ??
            profile?['username'] as String? ??
            AppLanguage.instance.text('unknownUser'),
      );
    }
    return names.isEmpty
        ? AppLanguage.instance.text('unknownUser')
        : names.join(', ');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr(context, 'chats')),
      actions: [
        IconButton(
          tooltip: tr(context, 'newChat'),
          icon: const Icon(Icons.add),
          onPressed: () => Navigator.pushNamed(context, '/newConversation'),
        ),
        IconButton(
          tooltip: tr(context, 'settings'),
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => Navigator.pushNamed(context, '/settings'),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => Navigator.pushNamed(context, '/newConversation'),
      icon: const Icon(Icons.chat_bubble_outline),
      label: Text(tr(context, 'newChat')),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream:
              FirebaseFirestore.instance
                  .collection('conversations')
                  .where('participants', arrayContains: currentUser.uid)
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(tr(context, errorKey(snapshot.error!))),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.data!.docs.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    tr(context, 'noChats'),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                final room = snapshot.data!.docs[index], data = room.data();
                return FutureBuilder<String>(
                  future: _displayName(context, data),
                  builder: (context, name) {
                    final label = name.data ?? tr(context, 'unknownUser');
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 10,
                      ),
                      leading: CircleAvatar(
                        child: Icon(
                          data['isGroup'] == true
                              ? Icons.group_outlined
                              : Icons.person_outline,
                        ),
                      ),
                      title: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        data['lastMessage'] as String? ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap:
                          () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder:
                                  (_) => ChatScreen(
                                    conversationId: room.id,
                                    otherUserName: label,
                                  ),
                            ),
                          ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    ),
  );
}
