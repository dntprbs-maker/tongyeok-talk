import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_screen.dart';
import 'app_language.dart';
import 'ui_errors.dart';
import 'read_receipts.dart';
import 'notification_prompt.dart';
import 'query_audit.dart';
import 'settings_screen.dart';
import 'translation_wallet.dart';
import 'reward_ad_service.dart';
import 'reward_ads_screen.dart';
import 'reward_platform.dart' as reward_platform;
import 'guest_rooms_list.dart';

import 'package:intl/intl.dart';
import 'referral_screen.dart';

class RecentConversationsScreen extends StatefulWidget {
  const RecentConversationsScreen({super.key});
  @override
  State<RecentConversationsScreen> createState() =>
      _RecentConversationsScreenState();
}

class _RecentConversationsScreenState extends State<RecentConversationsScreen> {
  final currentUser = FirebaseAuth.instance.currentUser!;

  @override
  void initState() {
    super.initState();
    _stopRewardListener = reward_platform.listenAvailability(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showReferralAnnouncement(context, currentUser.uid);
    });
  }

  final _prompt = GlobalKey<NotificationPromptState>();
  final _names = <String, Future<Map<String, dynamic>?>>{};
  final _roomNames = <String, Future<String>>{};
  late final void Function() _stopRewardListener;
  @override
  void dispose() {
    _stopRewardListener();
    super.dispose();
  }

  late final _rewardProfile =
      FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .snapshots();

  Widget _watchAdsButton() => FilledButton.icon(
    icon: const Icon(Icons.play_arrow_rounded, size: 18),
    label: Text(tr(context, 'watchAds'), textAlign: TextAlign.center),
    style: FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      minimumSize: const Size(0, 44),
      backgroundColor: const Color(0xFF0739E4),
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    onPressed:
        () => Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const RewardAdsScreen()),
        ),
  );

  Widget _rewardSummary() =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _rewardProfile,
        builder: (context, snapshot) {
          final profile = snapshot.data?.data();
          final enabled = profile?['rewardAdEnabled'] == true;
          final canWatch =
              rewardAdsSupported && (enabled || rewardPlaybackTest);
          return Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFEBF3FE),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TranslationWallet(
                    compact: true,
                    balanceOnly: true,
                    showLeaderPass:
                        profile != null &&
                        profile['preferredLanguage'] == 'Korean',
                  ),
                ),
                if (canWatch) ...[
                  const SizedBox(width: 10),
                  Flexible(child: _watchAdsButton()),
                ],
              ],
            ),
          );
        },
      );
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
    backgroundColor: Colors.white,
    appBar: AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      title: Text(
        tr(context, 'chats'),
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      actions: [
        IconButton(
          tooltip: tr(context, 'findPeople'),
          icon: const Icon(Icons.search),
          onPressed: () => _open('/newConversation'),
        ),
        IconButton(
          tooltip: tr(context, 'pastChats'),
          icon: const Icon(Icons.history),
          onPressed: () => _open('/pastChats'),
        ),
        NotificationPrompt(
          key: _prompt,
          iconOnly: true,
          onOpenSettings: () async {
            await Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const IncomingNoticesScreen(),
              ),
            );
            _prompt.currentState?.refresh();
          },
        ),
        IconButton(
          tooltip: tr(context, 'settings'),
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => _open('/settings'),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _rewardSummary()),
              SliverToBoxAdapter(child: GuestRoomsList()),
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
                    padding: const EdgeInsets.symmetric(horizontal: 16),
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
                            return Container(
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Color(0xFFF0F1F4)),
                                ),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 0,
                                  vertical: 10,
                                ),
                                leading: UnreadAvatar(
                                  key: ValueKey('unread-${room.id}'),
                                  conversationId: room.id,
                                  uid: currentUser.uid,
                                  displayName: label,
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
                                trailing:
                                    data['timestamp'] is Timestamp
                                        ? Text(
                                          DateFormat(
                                            'MM.dd HH:mm',
                                            AppLanguage.instance.code,
                                          ).format(
                                            (data['timestamp'] as Timestamp)
                                                .toDate()
                                                .toLocal(),
                                          ),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF757D8B),
                                          ),
                                        )
                                        : null,
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

class IncomingNoticesScreen extends StatefulWidget {
  const IncomingNoticesScreen({super.key});
  @override
  State<IncomingNoticesScreen> createState() => _IncomingNoticesScreenState();
}

class _IncomingNoticesScreenState extends State<IncomingNoticesScreen> {
  final currentUser = FirebaseAuth.instance.currentUser!;
  final _names = <String, Future<Map<String, dynamic>?>>{};
  late final _rooms =
      FirebaseFirestore.instance
          .collection('conversations')
          .where('participants', arrayContains: currentUser.uid)
          .orderBy('timestamp', descending: true)
          .snapshots();

  Future<String> _displayName(Map<String, dynamic> data) async {
    final group = data['groupName'] as String?;
    if (group != null && group.trim().isNotEmpty) return group;
    final names = <String>[];
    final participants = List<String>.from(data['participants'] as List? ?? []);
    for (final uid in participants.where((id) => id != currentUser.uid)) {
      final profile = await _names.putIfAbsent(uid, () async {
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

  Future<String> _senderName(String uid) async {
    final profile = await _names.putIfAbsent(uid, () async {
      auditQuery('profile_get');
      return (await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get())
          .data();
    });
    return profile?['displayName'] as String? ??
        profile?['username'] as String? ??
        AppLanguage.instance.text('unknownUser');
  }

  final _notices = <String, Future<_IncomingNotice?>>{};
  String _combinedKey = '';
  Future<List<_IncomingNotice?>>? _combined;

  Future<_IncomingNotice?> _notice(
    String roomId,
    Map<String, dynamic> room,
    Timestamp? revision,
  ) {
    final key = '$roomId@${revision?.millisecondsSinceEpoch ?? 0}';
    return _notices.putIfAbsent(key, () => _loadNotice(roomId, room));
  }

  Future<_IncomingNotice?> _loadNotice(
    String roomId,
    Map<String, dynamic> room,
  ) async {
    final receipt = await ReadReceipts.ref(roomId, currentUser.uid).get();
    final through = receipt.data()?['readThrough'] as Timestamp?;
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('conversations')
        .doc(roomId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(30);
    if (through != null) {
      query = query.where('timestamp', isGreaterThan: through);
    }
    auditQuery('incoming_notice_query');
    final result = await query.get();
    final docs =
        result.docs
            .where((d) => (d.data()['senderId'] as String?) != currentUser.uid)
            .toList();
    if (docs.isEmpty) return null;
    final message = docs.first.data();
    final senderId = message['senderId'] as String?;
    if (senderId == null) return null;
    return _IncomingNotice(
      roomName: await _displayName(room),
      senderName: await _senderName(senderId),
      text: message['originalText'] as String? ?? '',
      timestamp: message['timestamp'] as Timestamp?,
    );
  }

  Future<void> _openNotice(String roomId, String roomName) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder:
            (_) => ChatScreen(conversationId: roomId, otherUserName: roomName),
      ),
    );
    _notices.removeWhere((key, _) => key.startsWith('$roomId@'));
    if (mounted) setState(() => _combinedKey = '');
  }

  Widget _noticeTile(
    QueryDocumentSnapshot<Map<String, dynamic>> room,
    _IncomingNotice notice,
  ) {
    final data = room.data();
    return ListTile(
      leading: UnreadAvatar(
        key: ValueKey(room.id),
        conversationId: room.id,
        uid: currentUser.uid,
        displayName: notice.roomName,
        group: data['isGroup'] == true,
        messageRevision: data['timestamp'] as Timestamp?,
      ),
      title: Text(
        notice.senderName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(notice.text, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing:
          notice.timestamp == null
              ? null
              : Text(
                DateFormat(
                  'MM.dd HH:mm',
                  AppLanguage.instance.code,
                ).format(notice.timestamp!.toDate().toLocal()),
                style: const TextStyle(fontSize: 11, color: Color(0xFF757D8B)),
              ),
      onTap: () => _openNotice(room.id, notice.roomName),
    );
  }

  Widget _empty(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.notifications_none,
          size: 48,
          color: Color(0xFF7581CA),
        ),
        const SizedBox(height: 16),
        Text(tr(context, 'noticeEmpty'), textAlign: TextAlign.center),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr(context, 'noticesTitle')),
      actions: [
        IconButton(
          tooltip: tr(context, 'settings'),
          icon: const Icon(Icons.settings_outlined),
          onPressed:
              () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const SettingsScreen(showNotifications: true),
                ),
              ),
        ),
      ],
    ),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _rooms,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(tr(context, errorKey(snapshot.error!))),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return _empty(context);
        final signature = docs
            .map(
              (d) =>
                  '${d.id}@${(d.data()['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0}',
            )
            .join('|');
        if (signature != _combinedKey) {
          _combinedKey = signature;
          _combined = Future.wait(<Future<_IncomingNotice?>>[
            for (final room in docs)
              _notice(
                room.id,
                room.data(),
                room.data()['timestamp'] as Timestamp?,
              ),
          ]);
        }
        return FutureBuilder<List<_IncomingNotice?>>(
          future: _combined,
          builder: (context, all) {
            if (all.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (all.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(tr(context, errorKey(all.error!))),
                ),
              );
            }
            final notices = all.data ?? const <_IncomingNotice?>[];
            final rows = <Widget>[
              for (var i = 0; i < docs.length && i < notices.length; i++)
                if (notices[i] != null) _noticeTile(docs[i], notices[i]!),
            ];
            if (rows.isEmpty) return Center(child: _empty(context));
            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: rows,
            );
          },
        );
      },
    ),
  );
}

class _IncomingNotice {
  final String roomName, senderName, text;
  final Timestamp? timestamp;
  const _IncomingNotice({
    required this.roomName,
    required this.senderName,
    required this.text,
    required this.timestamp,
  });
}
