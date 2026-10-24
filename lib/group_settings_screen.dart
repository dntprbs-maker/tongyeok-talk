import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class GroupSettingsScreen extends StatefulWidget {
  final String conversationId;

  const GroupSettingsScreen({Key? key, required this.conversationId})
    : super(key: key);

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _currentUser = FirebaseAuth.instance.currentUser!;
  late TextEditingController _groupNameController;

  List<Map<String, dynamic>> _participants = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _groupNameController = TextEditingController();
    _loadGroupData();
  }

  Future<void> _loadGroupData() async {
    final doc =
        await _firestore
            .collection('conversations')
            .doc(widget.conversationId)
            .get();

    final data = doc.data();
    if (data == null) return;

    final groupName = data['groupName'] ?? '';
    _groupNameController.text = groupName;

    final participants = (data['participants'] as List).cast<String>();

    final List<Map<String, dynamic>> users = [];
    for (final uid in participants) {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      if (userDoc.exists) {
        users.add({
          'uid': uid,
          'username': userDoc.data()?['username'] ?? 'Unknown',
        });
      }
    }

    setState(() {
      _participants = users;
      _isLoading = false;
    });
  }

  Future<void> _updateGroupName() async {
    final newName = _groupNameController.text.trim();
    if (newName.isEmpty) return;
    await _firestore
        .collection('conversations')
        .doc(widget.conversationId)
        .update({'groupName': newName});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Group name updated')));
  }

  Future<void> _leaveGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Leave Group'),
            content: const Text(
              'Are you sure you want to leave this group? You won’t receive future messages.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Leave'),
              ),
            ],
          ),
    );

    if (confirm == true) {
      await _firestore
          .collection('conversations')
          .doc(widget.conversationId)
          .update({
            'participants': FieldValue.arrayRemove([_currentUser.uid]),
          });
      if (!mounted) return;
      Navigator.popUntil(context, ModalRoute.withName('/recentConversations'));
    }
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(title: const Text('Group Settings')),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        TextField(
                          controller: _groupNameController,
                          decoration: const InputDecoration(
                            labelText: 'Group Name',
                            border: OutlineInputBorder(),
                          ),
                          style: TextStyle(fontSize: isMobile ? 14 : 16),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _updateGroupName,
                          child: const Text('Save Group Name'),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Participants',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.exit_to_app),
                          label: const Text('Leave Group'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _participants.length,
                            itemBuilder: (context, index) {
                              final user = _participants[index];
                              return ListTile(
                                leading: const Icon(Icons.person_outline),
                                title: Text(user['username']),
                              );
                            },
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
