import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_service.dart';
import 'chat_screen.dart';

class NewConversationScreen extends StatefulWidget {
  const NewConversationScreen({super.key});

  @override
  State<NewConversationScreen> createState() => _NewConversationScreenState();
}

class _NewConversationScreenState extends State<NewConversationScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ChatService _chatService = ChatService();
  final User currentUser = FirebaseAuth.instance.currentUser!;
  final List<Map<String, dynamic>> _selectedUsers = [];

  bool _isGroupChat = false;
  List<String> _previousUsernames = [];
  List<String> _filteredSuggestions = [];

  @override
  void initState() {
    super.initState();
    _loadRecentUsernames();
    _searchController.addListener(_filterSuggestions);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterSuggestions);
    _searchController.dispose();
    super.dispose();
  }

  void _filterSuggestions() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredSuggestions =
          _previousUsernames
              .where(
                (name) =>
                    name.toLowerCase().startsWith(query) &&
                    !_selectedUsers.any((user) => user['username'] == name),
              )
              .toList();
    });
  }

  Future<void> _loadRecentUsernames() async {
    final snapshot =
        await _firestore
            .collection('conversations')
            .where('participants', arrayContains: currentUser.uid)
            .orderBy('timestamp', descending: true)
            .limit(30)
            .get();

    final Set<String> usernames = {};

    for (var doc in snapshot.docs) {
      final participants = (doc.data()['participants'] as List<dynamic>)
          .cast<String>()
          .where((id) => id != currentUser.uid);

      for (String uid in participants) {
        final userDoc = await _firestore.collection('users').doc(uid).get();
        final username = userDoc.data()?['username'];
        if (username != null && username is String) {
          usernames.add(username);
        }
      }
    }

    if (mounted) {
      setState(() {
        _previousUsernames =
            usernames.where((name) => name.isNotEmpty).toList();
      });
    }
  }

  Future<QuerySnapshot> _searchUsers(String query) {
    return _firestore
        .collection('users')
        .where('username', isEqualTo: query)
        .get();
  }

  void _startConversationWithUser(
    String otherUserId,
    String otherUserName,
  ) async {
    final conversationId = await _chatService.createOrGetConversation(
      currentUser.uid,
      otherUserId,
    );

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder:
            (_) => ChatScreen(
              conversationId: conversationId,
              otherUserName: otherUserName,
            ),
      ),
    );
  }

  void _addUserToGroup(Map<String, dynamic> userData) {
    if (_selectedUsers.any((user) => user['uid'] == userData['uid'])) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('User already added')));
      }
    } else {
      setState(() {
        _selectedUsers.add(userData);
      });
    }
  }

  Future<void> _createGroupConversation() async {
    if (_selectedUsers.isEmpty) return;

    final participantIds =
        _selectedUsers.map((u) => u['uid'] as String).toList();
    participantIds.add(currentUser.uid);

    final groupName = _generateGroupName(_selectedUsers);

    final docRef = await _firestore.collection('conversations').add({
      'participants': participantIds,
      'isGroup': true,
      'groupName': groupName,
      'timestamp': FieldValue.serverTimestamp(),
      'lastMessage': '',
    });

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder:
            (_) =>
                ChatScreen(conversationId: docRef.id, otherUserName: groupName),
      ),
    );
  }

  String _generateGroupName(List<Map<String, dynamic>> users) {
    if (users.length == 1) return users[0]['username'];
    if (users.length == 2) {
      return "${users[0]['username']} and ${users[1]['username']}";
    }
    if (users.length == 3) {
      return "${users[0]['username']}, ${users[1]['username']}, and ${users[2]['username']}";
    }
    return "${users[0]['username']}, ${users[1]['username']}, and ${users.length - 2} others";
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'New Conversation',
          style: TextStyle(fontSize: isMobile ? 18 : 20),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('New Group Chat'),
                  value: _isGroupChat,
                  onChanged: (value) => setState(() => _isGroupChat = value),
                  activeColor: Colors.white,
                  activeTrackColor: Colors.blue,
                  inactiveThumbColor: Colors.grey.shade400,
                  inactiveTrackColor: Colors.grey.shade300,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  style: TextStyle(fontSize: isMobile ? 14 : 16),
                  enabled: !_isGroupChat || _selectedUsers.length < 10,
                  decoration: InputDecoration(
                    labelText: 'Enter username',
                    labelStyle: TextStyle(fontSize: isMobile ? 14 : 16),
                    helperText:
                        _isGroupChat && _selectedUsers.length >= 10
                            ? 'Maximum 10 users allowed in a group'
                            : null,
                    helperStyle: const TextStyle(color: Colors.red),
                  ),
                ),
                if (_filteredSuggestions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.black12),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _filteredSuggestions.length,
                      itemBuilder: (context, index) {
                        final username = _filteredSuggestions[index];
                        return InkWell(
                          onTap: () => _searchController.text = username,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 16,
                            ),
                            decoration: BoxDecoration(
                              border:
                                  index != _filteredSuggestions.length - 1
                                      ? const Border(
                                        bottom: BorderSide(
                                          color: Colors.grey,
                                          width: 0.3,
                                        ),
                                      )
                                      : null,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.person_outline,
                                  size: 20,
                                  color: Colors.black54,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  username,
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 12),
                if (_isGroupChat && _selectedUsers.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children:
                          _selectedUsers.map((user) {
                            return Chip(
                              label: Text(user['username']),
                              deleteIcon: const Icon(Icons.close),
                              onDeleted: () {
                                setState(() {
                                  _selectedUsers.removeWhere(
                                    (u) => u['uid'] == user['uid'],
                                  );
                                });
                                _filterSuggestions();
                              },
                            );
                          }).toList(),
                    ),
                  ),
                ElevatedButton(
                  onPressed: () async {
                    if (_isGroupChat && _selectedUsers.length >= 10) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Maximum 10 users allowed in a group',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                      return;
                    }

                    final query = _searchController.text.trim();
                    if (query.isNotEmpty) {
                      final snapshot = await _searchUsers(query);
                      if (!mounted) return;

                      if (snapshot.docs.isNotEmpty) {
                        final userDoc = snapshot.docs.first;
                        final userId = userDoc.id;
                        final userData = userDoc.data() as Map<String, dynamic>;
                        final username = userData['username'] ?? 'Unknown';

                        final user = {'uid': userId, 'username': username};

                        if (_isGroupChat) {
                          _addUserToGroup(user);
                          _searchController.clear();
                        } else {
                          _searchController.clear();
                          _startConversationWithUser(userId, username);
                        }
                      } else {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('User not found')),
                          );
                        }
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 20 : 24,
                      vertical: isMobile ? 12 : 16,
                    ),
                  ),
                  child: Text(
                    _isGroupChat ? 'Add to List' : 'Start Conversation',
                    style: TextStyle(fontSize: isMobile ? 14 : 16),
                  ),
                ),
                if (_isGroupChat && _selectedUsers.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.group_add),
                      onPressed: _createGroupConversation,
                      label: Text(
                        'Create Group Chat',
                        style: TextStyle(fontSize: isMobile ? 14 : 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 20 : 24,
                          vertical: isMobile ? 12 : 16,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
