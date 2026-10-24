// Legacy entry point retained; global user listing is no longer exposed.
import 'package:flutter/material.dart';
import 'new_conversation_screen.dart';

class ConversationSelection extends StatelessWidget {
  const ConversationSelection({super.key});
  @override
  Widget build(BuildContext context) => const NewConversationScreen();
}
