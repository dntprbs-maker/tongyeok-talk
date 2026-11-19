import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import 'message_bubble.dart';
import 'group_settings_screen.dart';
import 'app_language.dart';
import 'ui_errors.dart';
import 'read_receipts.dart';
import 'message_history.dart';
import 'safety_controls.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String otherUserName;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.otherUserName,
  });

  @override
  ChatScreenState createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen>
    with WidgetsBindingObserver, RouteAware {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final User _currentUser = FirebaseAuth.instance.currentUser!;

  List<Map<String, dynamic>> _msgList = [];
  bool _isInitialLoad = true;
  bool _isGroupChat = false;
  bool _sending = false;
  int _messageLimit = 2000;
  Timestamp? _visibleThrough, _markedThrough;
  bool _marking = false;
  final Map<String, Timestamp> _receipts = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _receiptSubscription;
  final Set<String> _retrying = {};
  ModalRoute<void>? _route;
  late final MessageHistory _history;
  String? _newestShown;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route) {
      chatRouteObserver.unsubscribe(this);
      _route = route;
      if (route != null) chatRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() => _markVisibleRead();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _markVisibleRead();
  }

  Future<void> _markVisibleRead() async {
    final through = _visibleThrough;
    if (!mounted ||
        _marking ||
        through == null ||
        _route?.isCurrent != true ||
        (WidgetsBinding.instance.lifecycleState != null &&
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed) ||
        (_markedThrough != null && through.compareTo(_markedThrough!) <= 0)) {
      return;
    }
    _marking = true;
    try {
      await ReadReceipts.mark(widget.conversationId, _currentUser.uid, through);
      _markedThrough = through;
    } catch (_) {
      // Keep unread intact on failure; reopening/reconnecting retries safely.
    } finally {
      _marking = false;
    }
    if (_markedThrough == through && _visibleThrough != through) {
      _markVisibleRead();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _history = MessageHistory(FirestoreMessageSource(widget.conversationId));
    _receiptSubscription = FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.conversationId)
        .collection('reads')
        .snapshots()
        .listen((snapshot) {
          if (!mounted) return;
          setState(() {
            _receipts.clear();
            for (final doc in snapshot.docs) {
              final value = doc.data()['readThrough'];
              if (doc.id != _currentUser.uid && value is Timestamp) {
                _receipts[doc.id] = value;
              }
            }
          });
        }, onError: (_) {});
    _fetchParticipantsAndLanguages().catchError((_) {}).whenComplete(() {
      if (mounted) {
        setState(() => _isInitialLoad = false);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    chatRouteObserver.unsubscribe(this);
    _receiptSubscription?.cancel();
    _history.dispose();
    _scrollController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  /// Called whenever screen metrics change (e.g. keyboard open/close).
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  Future<void> _fetchParticipantsAndLanguages() async {
    final convDoc =
        await FirebaseFirestore.instance
            .collection('conversations')
            .doc(widget.conversationId)
            .get();
    if (!convDoc.exists) return;

    final data = convDoc.data();
    if (data == null) return;

    _isGroupChat = (data['isGroup'] ?? false) as bool;
    final participants = List<String>.from(data['participants'] as List? ?? []);
    if (participants.length != 2) return;
    final profiles = await Future.wait(
      participants.map(
        (uid) => FirebaseFirestore.instance.collection('users').doc(uid).get(),
      ),
    );
    final languages = <String>{};
    for (final profile in profiles) {
      final value = profile.data();
      if (value?['rewardAdEnabled'] != true) return;
      final language = value?['preferredLanguage'];
      if (language is String) languages.add(language);
    }
    if (languages.containsAll(['Korean', 'Mongolian'])) _messageLimit = 50;
  }

  Future<void> _sendMessage() async {
    if (_sending) return;
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    if ((_messageLimit == 50 ? text.runes.length : text.length) >
        _messageLimit) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              _messageLimit == 50 ? 'adMessageTooLong' : 'messageTooLong',
            ),
          ),
        ),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      final source = AppLanguage.instance.code;
      final room = FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId);
      final batch = FirebaseFirestore.instance.batch();
      batch.set(room.collection('messages').doc(), {
        'senderId': _currentUser.uid,
        'originalText': text,
        'translations': <String, String>{},
        'timestamp': FieldValue.serverTimestamp(),
        'sourceLang': source,
      });
      batch.update(room, {
        'lastMessage': text,
        'timestamp': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      _messageController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(tr(context, errorKey(e)))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _reportTranslation(
    Map<String, dynamic> msg,
    String translation,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(tr(context, 'reportTranslation')),
            content: Text(tr(context, 'reportTranslationConfirm')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr(context, 'cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(tr(context, 'reportTranslation')),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    final db = FirebaseFirestore.instance;
    final report = db
        .collection('conversations')
        .doc(widget.conversationId)
        .collection('messages')
        .doc(msg['id'] as String)
        .collection('translationReports')
        .doc(_currentUser.uid);
    final source = msg['sourceLang'] as String;
    try {
      final added = await db.runTransaction((tx) async {
        if ((await tx.get(report)).exists) return false;
        tx.set(report, {
          'original': msg['originalText'],
          'source': source,
          'target': source == 'ko' ? 'mn' : 'ko',
          'translation': translation,
          'createdAt': FieldValue.serverTimestamp(),
        });
        return true;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                context,
                added ? 'translationReportSent' : 'translationReportExists',
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(tr(context, errorKey(error)))));
      }
    }
  }

  Future<void> _retryTranslation(String messageId) async {
    if (!_retrying.add(messageId)) return;
    setState(() {});
    try {
      await FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId)
          .collection('translationRetries')
          .add({
            'messageId': messageId,
            'requestedBy': _currentUser.uid,
            'requestedAt': FieldValue.serverTimestamp(),
          });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'translationRequested'))),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(tr(context, errorKey(error)))));
      }
    } finally {
      _retrying.remove(messageId);
      if (mounted) setState(() {});
    }
  }

  void _scrollToBottom([int attempts = 5]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController
            .animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
            )
            .then((_) {
              // Variable-height bilingual bubbles refine the lazy list's extent
              // after layout. Follow the refined end, without a permanent loop.
              if (mounted &&
                  attempts > 0 &&
                  _scrollController.hasClients &&
                  _scrollController.position.extentAfter > 2) {
                _scrollToBottom(attempts - 1);
              }
            });
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
            colors: [Color(0xFFE4EBF3), Color(0xFFE4EBF3)],
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
        color: Colors.white.withValues(alpha: 0.75),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
      child: Row(
        children: [
          IconButton(
            tooltip: tr(context, 'back'),
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
          IconButton(
            tooltip: tr(context, 'preview'),
            icon: const Icon(Icons.info_outline, size: 21),
            onPressed:
                () => showDialog<void>(
                  context: context,
                  builder:
                      (context) => AlertDialog(
                        content: Text(
                          '${tr(context, 'preview')}\n\n${tr(context, 'chatDeliveryNotice')}',
                        ),
                      ),
                ),
          ),
          IconButton(
            tooltip: tr(context, 'safetyTitle'),
            icon: const Icon(Icons.shield_outlined, size: 21),
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => SafetyControls(
                          conversationId: widget.conversationId,
                        ),
                  ),
                ),
          ),
          if (_isGroupChat)
            IconButton(
              tooltip: tr(context, 'groupSettings'),
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
    return AnimatedBuilder(
      animation: _history,
      builder: (ctx, _) {
        if (!_history.ready) {
          return const SizedBox();
        }
        if (_history.error != null && _history.messages.isEmpty) {
          return Center(child: Text(tr(context, errorKey(_history.error!))));
        }
        final docs = _history.messages;
        if (docs.isEmpty) {
          return Center(child: Text(tr(context, 'noMessages')));
        }

        for (final doc in docs) {
          final value = doc.data()?['timestamp'];
          if (!doc.metadata.hasPendingWrites &&
              value is Timestamp &&
              (_visibleThrough == null ||
                  value.compareTo(_visibleThrough!) > 0)) {
            _visibleThrough = value;
          }
        }
        WidgetsBinding.instance.addPostFrameCallback((_) => _markVisibleRead());

        final previousNewest = _msgList.isEmpty ? null : _msgList.last;
        final nearBottom =
            !_scrollController.hasClients ||
            _scrollController.position.extentAfter < 100;

        // Build local list
        _msgList =
            docs.map((doc) {
              final data = doc.data()!;
              final senderId = data['senderId'] ?? '';
              final originalText = data['originalText'] ?? '';
              final ts = data['timestamp'] as Timestamp?;
              final dt = ts?.toDate() ?? DateTime.now();
              final sourceLang = data['sourceLang'] ?? 'ko';
              final translations =
                  data['translations'] as Map<String, dynamic>? ?? {};

              final isMe = senderId == _currentUser.uid;
              final targetLang = sourceLang == 'ko' ? 'mn' : 'ko';
              final translatedText = translations[targetLang] as String? ?? '';
              final status = data['translationStatus'] as String? ?? 'pending';
              final others =
                  _receipts.values
                      .where((value) => ts != null && value.compareTo(ts) >= 0)
                      .length;

              return {
                'senderId': senderId,
                'originalText': originalText,
                'translatedText': translatedText,
                'timestamp': dt,
                'sourceLang': sourceLang,
                'targetLang': targetLang,
                'id': doc.id,
                'translationStatus': status,
                'creditManaged': data['creditManaged'] == true,
                'sent': !doc.metadata.hasPendingWrites,
                'read': isMe && others > 0,
                'retryAllowed':
                    (data['translationAttempts'] as num? ?? 0) < 3 &&
                    status == 'failed',
              };
            }).toList();

        // Follow the latest message near the bottom when its translation
        // changes the row height or adds the language button.
        final newest = _msgList.last;
        final newestId = docs.last.id;
        final newestChanged =
            newestId != _newestShown ||
            previousNewest?['translationStatus'] !=
                newest['translationStatus'] ||
            previousNewest?['translatedText'] != newest['translatedText'];
        if (_newestShown == null || (nearBottom && newestChanged)) {
          _scrollToBottom();
        }
        _newestShown = newestId;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView.builder(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _msgList.length + 1,
              itemBuilder: (ctx, position) {
                if (position == 0) {
                  return Center(
                    child:
                        _history.loadingOlder
                            ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(),
                            )
                            : (_history.hasOlder || _history.pageError != null)
                            ? TextButton(
                              onPressed: _loadOlder,
                              child: Text(
                                tr(
                                  context,
                                  _history.pageError == null
                                      ? 'olderMessages'
                                      : 'historyRetry',
                                ),
                              ),
                            )
                            : const SizedBox(height: 8),
                  );
                }
                final index = position - 1;
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

                Widget buildBubble(String translation, String status) =>
                    MessageBubble(
                      key: ValueKey(msg['id']),
                      senderId: msg['senderId'] as String,
                      currentUserId: _currentUser.uid,
                      originalText: msg['originalText'] as String,
                      translatedText: translation,
                      timestamp: dt,
                      sourceLang: msg['sourceLang'] as String?,
                      targetLang: msg['targetLang'] as String?,
                      translationStatus: status,
                      sent: msg['sent'] as bool,
                      read: msg['read'] as bool,
                      onReportTranslation:
                          status == 'done' &&
                                  translation.trim().isNotEmpty &&
                                  msg['sourceLang'] != msg['targetLang']
                              ? () => _reportTranslation(msg, translation)
                              : null,
                      onRetry:
                          ((status == 'failed' &&
                                          (msg['creditManaged'] == true ||
                                              msg['retryAllowed'] == true)) ||
                                      (msg['translationStatus'] == 'pending' &&
                                          DateTime.now()
                                                  .difference(dt)
                                                  .inSeconds >
                                              60)) &&
                                  !_retrying.contains(msg['id'])
                              ? () => _retryTranslation(msg['id'] as String)
                              : null,
                    );

                final bubble =
                    msg['creditManaged'] == true
                        ? _CreditTranslation(
                          key: ValueKey(msg['id']),
                          access: FirebaseFirestore.instance
                              .collection('conversations')
                              .doc(widget.conversationId)
                              .collection('messages')
                              .doc(msg['id'] as String)
                              .collection('creditTranslations')
                              .doc(_currentUser.uid),
                          builder: buildBubble,
                        )
                        : buildBubble(
                          msg['translatedText'] as String,
                          msg['translationStatus'] as String,
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

  Future<void> _loadOlder() async {
    final oldExtent =
        _scrollController.hasClients
            ? _scrollController.position.maxScrollExtent
            : 0.0;
    final oldOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    _history.retryGaps();
    await _history.loadOlder();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final p = _scrollController.position;
      _scrollController.jumpTo(
        (oldOffset + p.maxScrollExtent - oldExtent).clamp(
          0.0,
          p.maxScrollExtent,
        ),
      );
    });
  }

  Widget _buildDayMarker(DateTime date) {
    final dayString = DateFormat(
      'y.M.d EEEE',
      AppLanguage.instance.code,
    ).format(date);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            dayString,
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      // ADDED: Slight frosted-white background & shadow for the bottom input bar
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: tr(context, 'message'),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              style: const TextStyle(fontSize: 15),
              buildCounter:
                  (
                    context, {
                    required currentLength,
                    required isFocused,
                    required maxLength,
                  }) =>
                      _messageLimit == 50 || currentLength >= 1800
                          ? Text('$currentLength/$maxLength')
                          : null,
              maxLength: _messageLimit,
              enabled: !_sending,
              onTap: _scrollToBottom,
            ),
          ),
          IconButton(
            tooltip: tr(context, 'send'),
            icon: const Icon(Icons.send),
            onPressed: _sending ? null : _sendMessage,
          ),
        ],
      ),
    );
  }
}

class _CreditTranslation extends StatefulWidget {
  const _CreditTranslation({
    super.key,
    required this.access,
    required this.builder,
  });

  final DocumentReference<Map<String, dynamic>> access;
  final Widget Function(String translation, String status) builder;

  @override
  State<_CreditTranslation> createState() => _CreditTranslationState();
}

class _CreditTranslationState extends State<_CreditTranslation> {
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _updates =
      widget.access.snapshots();

  @override
  void didUpdateWidget(covariant _CreditTranslation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.access != oldWidget.access) {
      _updates = widget.access.snapshots();
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: _updates,
    builder: (context, snapshot) {
      final data = snapshot.data?.data();
      return widget.builder(
        data?['translation'] as String? ?? '',
        snapshot.hasError
            ? 'unavailable'
            : data?['status'] as String? ?? 'pending',
      );
    },
  );
}
