import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import 'utils/languages.dart';
import 'message_bubble.dart';
import 'group_settings_screen.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String otherUserName;

  const ChatScreen({
    Key? key,
    required this.conversationId,
    required this.otherUserName,
  }) : super(key: key);

  @override
  ChatScreenState createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final User _currentUser = FirebaseAuth.instance.currentUser!;

  String? _otherUserId;
  String _otherUserLanguage = 'English';
  String _myLanguage = 'English';
  List<Map<String, dynamic>> _msgList = [];
  bool _isInitialLoad = true;
  bool _isGroupChat = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchParticipantsAndLanguages().then((_) {
      if (mounted) {
        setState(() => _isInitialLoad = false);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  /// Called whenever screen metrics change (e.g. keyboard open/close).
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  Future<void> _fetchParticipantsAndLanguages() async {
    final myUid = _currentUser.uid;
    final convDoc =
        await FirebaseFirestore.instance
            .collection('conversations')
            .doc(widget.conversationId)
            .get();
    if (!convDoc.exists) return;

    final data = convDoc.data();
    if (data == null) return;

    _isGroupChat = (data['isGroup'] ?? false) as bool;
    final participants = data['participants'] as List<dynamic>? ?? [];
    for (String uid in participants.cast<String>()) {
      if (uid != myUid) {
        _otherUserId = uid;
        break;
      }
    }
    if (_otherUserId == null) return;

    // Other user's language
    final otherDoc =
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_otherUserId!)
            .get();
    if (otherDoc.exists) {
      _otherUserLanguage =
          (otherDoc.data()?['preferredLanguage'] ?? 'English') as String;
    }

    // My language
    final myDoc =
        await FirebaseFirestore.instance.collection('users').doc(myUid).get();
    if (myDoc.exists) {
      _myLanguage = (myDoc.data()?['preferredLanguage'] ?? 'English') as String;
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();

    final myUid = _currentUser.uid;
    final convDoc =
        await FirebaseFirestore.instance
            .collection('conversations')
            .doc(widget.conversationId)
            .get();

    final data = convDoc.data();
    if (data == null) return;

    final myDoc =
        await FirebaseFirestore.instance.collection('users').doc(myUid).get();
    final myLang = (myDoc.data()?['preferredLanguage'] ?? 'English') as String;
    final sourceLang = _langToIso(myLang);

    // Original-only public preview: never fabricate a translation.
    final translations = <String,String>{};

    await FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.conversationId)
        .collection('messages')
        .add({
          'senderId': myUid,
          'originalText': text,
          'translations': translations,
          'timestamp': FieldValue.serverTimestamp(),
          'sourceLang': sourceLang,
        });

    await FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.conversationId)
        .update({
          'lastMessage': text,
          'timestamp': FieldValue.serverTimestamp(),
        });
  }

  String _langToIso(String lang) {
    return supportedLanguages[lang] ?? 'en';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Allows the chat to move above the keyboard
      resizeToAvoidBottomInset: true,
      // ADDED: Make the background a gradient
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE3F2FD), Color(0xFFF1F8E9)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child:
              _isInitialLoad
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                    children: [
                      _buildHeader(),
                      Expanded(child: _buildMessagesStream()),
                      _buildMessageInput(),
                    ],
                  ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      // ADDED: Slight frosted-white with boxShadow to make header stand out
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.75),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 16.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Text(
              widget.otherUserName,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_isGroupChat)
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => GroupSettingsScreen(
                          conversationId: widget.conversationId,
                        ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildMessagesStream() {
    return StreamBuilder<QuerySnapshot>(
      stream:
          FirebaseFirestore.instance
              .collection('conversations')
              .doc(widget.conversationId)
              .collection('messages')
              .orderBy('timestamp', descending: false)
              .snapshots(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox();
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('No messages yet.'));
        }

        // Build local list
        _msgList =
            docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final senderId = data['senderId'] ?? '';
              final originalText = data['originalText'] ?? '';
              final ts = data['timestamp'] as Timestamp?;
              final dt = ts?.toDate() ?? DateTime.now();
              final sourceLang = data['sourceLang'] ?? 'en';
              final translations =
                  data['translations'] as Map<String, dynamic>? ?? {};

              final isMe = senderId == _currentUser.uid;
              final translatedText =
                  isMe
                      ? (_isGroupChat
                          ? originalText
                          : (translations[_otherUserId] ?? originalText))
                      : (translations[_currentUser.uid] ?? originalText);

              final targetLang =
                  (isMe && _isGroupChat)
                      ? null
                      : _langToIso(isMe ? _otherUserLanguage : _myLanguage);

              return {
                'senderId': senderId,
                'originalText': originalText,
                'translatedText': translatedText,
                'timestamp': dt,
                'sourceLang': sourceLang,
                'targetLang': targetLang,
              };
            }).toList();

        // Scroll to bottom on new messages
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView.builder(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _msgList.length,
              itemBuilder: (ctx, index) {
                final msg = _msgList[index];
                final dt = msg['timestamp'] as DateTime;

                // Show day marker if new day
                Widget? dayMarker;
                if (index == 0) {
                  dayMarker = _buildDayMarker(dt);
                } else {
                  final prevDt = _msgList[index - 1]['timestamp'] as DateTime;
                  final isNewDay =
                      dt.year != prevDt.year ||
                      dt.month != prevDt.month ||
                      dt.day != prevDt.day;
                  if (isNewDay) {
                    dayMarker = _buildDayMarker(dt);
                  }
                }

                final bubble = MessageBubble(
                  senderId: msg['senderId'] as String,
                  currentUserId: _currentUser.uid,
                  originalText: msg['originalText'] as String,
                  translatedText: msg['translatedText'] as String,
                  timestamp: dt,
                  sourceLang: msg['sourceLang'] as String?,
                  targetLang: msg['targetLang'] as String?,
                );

                if (dayMarker != null) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [dayMarker, bubble],
                  );
                } else {
                  return bubble;
                }
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildDayMarker(DateTime date) {
    final dayString = DateFormat('EEEE, MMM d').format(date);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            dayString,
            style: const TextStyle(fontSize: 14, color: Colors.black54),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      // ADDED: Slight frosted-white background & shadow for the bottom input bar
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              minLines: 1,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Enter message'),
              onTap: _scrollToBottom,
            ),
          ),
          IconButton(icon: const Icon(Icons.send), onPressed: _sendMessage),
        ],
      ),
    );
  }
}
