import 'package:flutter/material.dart';

const homeCardBorderColor = Color(0xFFC4D2E5);

class ChatBubbleAvatar extends StatelessWidget {
  final bool group;
  const ChatBubbleAvatar({super.key, this.group = false});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 24,
    height: 24,
    child: Icon(
      group ? Icons.forum_outlined : Icons.chat_bubble_outline,
      size: 24,
      color: const Color(0xFF62758E),
    ),
  );
}

class ChatRowCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const ChatRowCard({super.key, required this.child, this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: homeCardBorderColor),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: child,
        ),
      ),
    ),
  );
}
