import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_screen.dart';
import 'chat_service.dart';

class RecentConversationsScreen extends StatelessWidget {
  RecentConversationsScreen({super.key});

  final User currentUser = FirebaseAuth.instance.currentUser!;
  final ChatService _chatService = ChatService();

  Stream<QuerySnapshot> getRecentConversations() {
    return FirebaseFirestore.instance
        .collection('conversations')
        .where('participants', arrayContains: currentUser.uid)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  Future<String> _getConversationDisplayName(
    List<dynamic> participants,
    String? groupName,
  ) async {
    if (groupName != null && groupName.trim().isNotEmpty) {
      return groupName;
    }

    final otherUserIds =
        participants
            .where((id) => id != currentUser.uid)
            .cast<String>()
            .toList();

    final usernames = <String>[];
    for (final uid in otherUserIds) {
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (userDoc.exists) {
        final data = userDoc.data();
        if (data != null && data['username'] != null) {
          usernames.add(data['username']);
        }
      }
    }

    if (usernames.isEmpty) return "Unknown";
    if (usernames.length == 1) return usernames.first;
    if (usernames.length == 2) return "${usernames[0]} and ${usernames[1]}";
    return "${usernames[0]}, ${usernames[1]}, and ${usernames.length - 2} others";
  }

  void _confirmDeleteConversation(
    BuildContext context,
    String conversationId,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete Conversation'),
            content: const Text(
              'Are you sure you want to delete this conversation for yourself?\nAll your messages will be removed. This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );

    if (shouldDelete == true) {
      await _chatService.deleteConversationForUser(
        conversationId,
        currentUser.uid,
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Conversation deleted.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final bool isMobile = screenSize.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Recent Conversations',
          style: TextStyle(fontSize: isMobile ? 18 : 20),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.pushNamed(context, '/newConversation'),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE3F2FD), Color(0xFFF1F8E9)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: StreamBuilder<QuerySnapshot>(
              stream: getRecentConversations(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: TextStyle(fontSize: isMobile ? 14 : 16),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No conversations yet.'));
                }

                final convos = snapshot.data!.docs;
                return ListView.builder(
                  itemCount: convos.length,
                  itemBuilder: (context, index) {
                    final convRef = convos[index];
                    final data = convRef.data() as Map<String, dynamic>;
                    final participants = data['participants'] as List<dynamic>;
                    final groupName = data['groupName'] as String?;

                    return FutureBuilder<String>(
                      future: _getConversationDisplayName(
                        participants,
                        groupName,
                      ),
                      builder: (context, nameSnapshot) {
                        final displayName = nameSnapshot.data ?? 'Conversation';
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12.0,
                            vertical: 6.0,
                          ),
                          child: Card(
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(16.0),
                              leading: CircleAvatar(
                                backgroundColor:
                                    Theme.of(context).colorScheme.secondary,
                                child: Text(
                                  displayName.isNotEmpty
                                      ? displayName[0].toUpperCase()
                                      : '?',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(color: Colors.white),
                                ),
                              ),
                              title: Text(
                                displayName,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              subtitle: FutureBuilder<QuerySnapshot>(
                                future:
                                    FirebaseFirestore.instance
                                        .collection('conversations')
                                        .doc(convRef.id)
                                        .collection('messages')
                                        .orderBy('timestamp', descending: true)
                                        .limit(1)
                                        .get(),
                                builder: (context, msgSnapshot) {
                                  if (!msgSnapshot.hasData ||
                                      msgSnapshot.data!.docs.isEmpty) {
                                    return const Text('');
                                  }

                                  final msgDoc = msgSnapshot.data!.docs.first;
                                  final msgData =
                                      msgDoc.data() as Map<String, dynamic>?;

                                  if (msgData == null) return const Text('');

                                  final originalText =
                                      msgData['originalText'] ?? '';
                                  final translations =
                                      msgData['translations']
                                          as Map<String, dynamic>? ??
                                      {};
                                  final translatedText =
                                      translations[currentUser.uid] ??
                                      originalText;

                                  return Text(
                                    translatedText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  );
                                },
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (context) => ChatScreen(
                                          conversationId: convRef.id,
                                          otherUserName: displayName,
                                        ),
                                  ),
                                );
                              },
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'delete') {
                                    _confirmDeleteConversation(
                                      context,
                                      convRef.id,
                                    );
                                  }
                                },
                                itemBuilder:
                                    (ctx) => [
                                      const PopupMenuItem(
                                        value: 'unavailable',
                                        enabled: false,
                                        child: Text('시험판: 삭제 기능 사용 안 함'),
                                      ),
                                    ],
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
      ),
    );
  }
}
