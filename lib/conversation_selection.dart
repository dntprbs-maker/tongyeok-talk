import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_service.dart';
import 'chat_screen.dart';

class ConversationSelection extends StatelessWidget {
  ConversationSelection({Key? key}) : super(key: key);

  final User currentUser = FirebaseAuth.instance.currentUser!;
  final ChatService _chatService = ChatService();

  // For demonstration, we query the 'users' collection
  Stream<QuerySnapshot> getUsers() {
    return FirebaseFirestore.instance.collection('users').snapshots();
  }

  Future<void> _startConversation(
    BuildContext context,
    String otherUserId,
    String otherUserName, // <-- NEW parameter here
  ) async {
    String conversationId = await _chatService.createOrGetConversation(
      currentUser.uid,
      otherUserId,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => ChatScreen(
              conversationId: conversationId,
              otherUserName: otherUserName, // pass the name along
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Responsive logic
    final Size screenSize = MediaQuery.of(context).size;
    final bool isMobile = screenSize.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Select a User',
          style: TextStyle(fontSize: isMobile ? 18 : 20),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: StreamBuilder<QuerySnapshot>(
            stream: getUsers(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final users = snapshot.data!.docs;
              if (users.isEmpty) {
                return const Center(child: Text('No users found.'));
              }
              return ListView.builder(
                itemCount: users.length,
                itemBuilder: (context, index) {
                  final data = users[index].data() as Map<String, dynamic>;
                  final userId = users[index].id;
                  if (userId == currentUser.uid) return const SizedBox.shrink();
                  final username = data['username'] ?? 'No Name';

                  return ListTile(
                    title: Text(
                      username,
                      style: TextStyle(fontSize: isMobile ? 14 : 16),
                    ),
                    // Pass BOTH the userId and the username
                    onTap: () => _startConversation(context, userId, username),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
