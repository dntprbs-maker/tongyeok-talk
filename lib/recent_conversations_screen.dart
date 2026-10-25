import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_screen.dart';
import 'app_language.dart';
import 'ui_errors.dart';
import 'read_receipts.dart';
import 'notification_prompt.dart';
import 'query_audit.dart';

class RecentConversationsScreen extends StatefulWidget {
  const RecentConversationsScreen({super.key});
  @override
  State<RecentConversationsScreen> createState() =>
      _RecentConversationsScreenState();
}

class _RecentConversationsScreenState extends State<RecentConversationsScreen> {
  final currentUser = FirebaseAuth.instance.currentUser!;
  final _prompt = GlobalKey<NotificationPromptState>();
  final _names = <String, Future<Map<String, dynamic>?>>{};
  final _roomNames = <String, Future<String>>{};
  late final _profile =
      FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
  late final _rooms =
      FirebaseFirestore.instance
          .collection('conversations')
          .where('participants', arrayContains: currentUser.uid)
          .orderBy('timestamp', descending: true)
          .snapshots();
  Future<void> _open(String route) async {
    await Navigator.pushNamed(context, route);
    _prompt.currentState?.refresh();
  }

  Future<String> _displayName(Map<String, dynamic> data) async {
    final group = data['groupName'] as String?;
    if (group != null && group.trim().isNotEmpty) return group;
    final names = <String>[];
    for (final uid in (data['participants'] as List).where(
      (id) => id != currentUser.uid,
    )) {
      final profile = await _names.putIfAbsent(uid as String, () async {
        auditQuery('profile_get');
        return (await FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .get())
            .data();
      });
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
    backgroundColor: const Color(0xFFF5F6FB),
    appBar: AppBar(
      backgroundColor: const Color(0xFFF5F6FB),
      title: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/images/interpreter-talk.png',
              width: 34,
              height: 34,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            tr(context, 'app'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: tr(context, 'settings'),
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => _open('/settings'),
        ),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: 0,
      onDestinationSelected: (index) {
        if (index == 1) _open('/newConversation');
        if (index == 2) _open('/settings');
      },
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.chat_bubble_outline),
          selectedIcon: const Icon(Icons.chat_bubble),
          label: tr(context, 'chats'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.person_search_outlined),
          label: tr(context, 'findPeople'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.settings_outlined),
          label: tr(context, 'settings'),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        future: _profile,
                        builder: (context, snapshot) {
                          final data = snapshot.data?.data();
                          return ConversationHomeHeading(
                            displayName:
                                data?['displayName'] as String? ??
                                data?['username'] as String? ??
                                '',
                            onNewChat: () => _open('/newConversation'),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      NotificationPrompt(key: _prompt),
                      Text(
                        tr(context, 'myConversations'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _rooms,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(tr(context, errorKey(snapshot.error!))),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const SliverToBoxAdapter(
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.data!.docs.isEmpty) {
                    return SliverPadding(
                      padding: const EdgeInsets.all(20),
                      sliver: SliverToBoxAdapter(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 40,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.forum_outlined,
                                size: 48,
                                color: Color(0xFF7581CA),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                tr(context, 'noChats'),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              OutlinedButton.icon(
                                onPressed: () => _open('/newConversation'),
                                icon: const Icon(Icons.person_search_outlined),
                                label: Text(tr(context, 'findPeople')),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList.builder(
                      itemCount: snapshot.data!.docs.length,
                      findChildIndexCallback: (key) {
                        if (key is! ValueKey<String>) return null;
                        final index = snapshot.data!.docs.indexWhere(
                          (d) => d.id == key.value,
                        );
                        return index < 0 ? null : index;
                      },
                      itemBuilder: (context, index) {
                        final room = snapshot.data!.docs[index],
                            data = room.data();
                        return FutureBuilder<String>(
                          key: ValueKey(room.id),
                          future: _roomNames.putIfAbsent(
                            '${room.id}/${data['groupName']}/${data['participants']}/${AppLanguage.instance.code}',
                            () => _displayName(data),
                          ),
                          builder: (context, name) {
                            final label =
                                name.data ?? tr(context, 'unknownUser');
                            return Card(
                              color: Colors.white,
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                leading: UnreadAvatar(
                                  key: ValueKey('unread-${room.id}'),
                                  conversationId: room.id,
                                  uid: currentUser.uid,
                                  group: data['isGroup'] == true,
                                  messageRevision:
                                      data['timestamp'] as Timestamp?,
                                ),
                                title: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 5),
                                  child: Text(
                                    data['lastMessage'] as String? ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right,
                                  size: 20,
                                  color: Color(0xFF9BA0B4),
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
                              ),
                            );
                          },
                        );
                      },
                    ),
                  );
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    ),
  );
}

class ConversationHomeHeading extends StatelessWidget {
  final String displayName;
  final VoidCallback onNewChat;
  const ConversationHomeHeading({
    super.key,
    required this.displayName,
    required this.onNewChat,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        displayName.isEmpty
            ? tr(context, 'homeGreeting')
            : tr(context, 'helloName', {'name': displayName}),
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      const SizedBox(height: 8),
      Text(
        tr(context, 'homeSubtitle'),
        style: const TextStyle(color: Color(0xFF646B82), height: 1.5),
      ),
      const SizedBox(height: 18),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onNewChat,
          icon: const Icon(Icons.add_comment_outlined),
          label: Text(tr(context, 'newChat')),
        ),
      ),
    ],
  );
}
