import 'package:flutter/material.dart';
import 'app_language.dart';

const memberChatColor = Color(0xFF585C94);
const guestChatColor = Color(0xFF207B72);

class ChatKindBadge extends StatelessWidget {
  final bool guest;
  const ChatKindBadge({super.key, required this.guest});
  @override
  Widget build(BuildContext context) {
    final color = guest ? guestChatColor : memberChatColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Text(
        tr(context, guest ? 'guestBadge' : 'memberBadge'),
        style: TextStyle(color: color, fontSize: 11),
      ),
    );
  }
}
