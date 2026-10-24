import 'package:cloud_firestore/cloud_firestore.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Create (or get) a conversation between two users.
  Future<String> createOrGetConversation(String userId1, String userId2) async {
    // Sort IDs so the order is consistent
    List<String> participants = [userId1, userId2]..sort();

    // Query for an existing conversation with these participants.
    QuerySnapshot snapshot =
        await _firestore
            .collection('conversations')
            .where('participants', isEqualTo: participants)
            .get();

    if (snapshot.docs.isNotEmpty) {
      // Conversation already exists.
      return snapshot.docs.first.id;
    } else {
      // Create a new conversation document.
      DocumentReference docRef = await _firestore
          .collection('conversations')
          .add({
            'participants': participants,
            'lastMessage': '',
            'timestamp': FieldValue.serverTimestamp(),
          });
      return docRef.id;
    }
  }

  // Send a message in a given conversation.
  Future<void> sendMessage(
    String conversationId,
    String message,
    String userId,
  ) async {
    // Add the message to the conversation's "messages" subcollection.
    await _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .add({
          'text': message,
          'senderId': userId,
          'timestamp': FieldValue.serverTimestamp(),
        });

    // Update conversation metadata (optional).
    await _firestore.collection('conversations').doc(conversationId).update({
      'lastMessage': message,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // Stream messages for a given conversation.
  Stream<QuerySnapshot> getMessages(String conversationId) {
    return _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  // Delete a conversation only for a specific user.
  // - Removes all messages from 'senderId' == userId
  // - Removes that user from the participants array
  Future<void> deleteConversationForUser(
    String conversationId,
    String userId,
  ) async {
    final conversationRef = _firestore
        .collection('conversations')
        .doc(conversationId);
    final messagesRef = conversationRef.collection('messages');

    // Query all messages from this user
    final query = await messagesRef.where('senderId', isEqualTo: userId).get();

    // Use a batch to delete multiple docs atomically
    WriteBatch batch = _firestore.batch();

    // 1) Delete the user's messages
    for (var doc in query.docs) {
      batch.delete(doc.reference);
    }

    // 2) Remove the user from participants
    batch.update(conversationRef, {
      'participants': FieldValue.arrayRemove([userId]),
    });

    // (Optional) If after removal the conversation has zero participants,
    // you could delete the entire conversation doc:
    final convSnapshot = await conversationRef.get();
    final data = convSnapshot.data();
    if (data != null) {
      final participants = data['participants'] as List<dynamic>? ?? [];
      if (participants.isEmpty) {
        batch.delete(conversationRef);
      }
    }

    await batch.commit();
  }
}
