import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'utils/languages.dart';

class MessageBubble extends StatefulWidget {
  final String senderId;
  final String currentUserId;
  final String originalText;
  final String translatedText;
  final DateTime timestamp;
  final String? sourceLang;
  final String? targetLang;

  const MessageBubble({
    Key? key,
    required this.senderId,
    required this.currentUserId,
    required this.originalText,
    required this.translatedText,
    required this.timestamp,
    this.sourceLang,
    this.targetLang,
  }) : super(key: key);

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  late bool _showOriginal;

  @override
  void initState() {
    super.initState();
    _showOriginal = widget.senderId == widget.currentUserId;
  }

  @override
  Widget build(BuildContext context) {
    final bool isMe = widget.senderId == widget.currentUserId;
    final timeString = DateFormat('h:mm a').format(widget.timestamp);
    final bool hasDifferentTranslation =
        widget.originalText != widget.translatedText &&
        widget.translatedText.isNotEmpty;
    final displayText =
        _showOriginal ? widget.originalText : widget.translatedText;

    // 🎨 Playful, modern colors
    final bubbleColor =
        isMe ? const Color(0xFF6A82FB) : const Color(0xFFF1F1F1);
    final textColor = isMe ? Colors.white : Colors.black87;
    final secondaryTextColor = isMe ? Colors.white70 : Colors.black45;
    final linkColor = isMe ? Colors.white : const Color(0xFF6A82FB);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth:
              MediaQuery.of(context).size.width < 600
                  ? MediaQuery.of(context).size.width * 0.75
                  : 500,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
          padding: const EdgeInsets.all(14.0),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(
                displayText,
                style: TextStyle(color: textColor, fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 6),
              Text(
                timeString,
                style: TextStyle(color: secondaryTextColor, fontSize: 12),
              ),
              if (hasDifferentTranslation &&
                  widget.sourceLang != null &&
                  widget.targetLang != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Translated from ${_getLangName(widget.sourceLang)} to ${_getLangName(widget.targetLang)}',
                    style: TextStyle(
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                      color: secondaryTextColor,
                    ),
                  ),
                ),
              if (hasDifferentTranslation)
                TextButton(
                  onPressed: () {
                    setState(() => _showOriginal = !_showOriginal);
                  },
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  child: Text(
                    _showOriginal ? 'View Translated' : 'View Original',
                    style: TextStyle(fontSize: 12, color: linkColor),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _getLangName(String? code) {
  if (code == null) return '';
  return supportedLanguages.entries
      .firstWhere(
        (entry) => entry.value == code,
        orElse: () => const MapEntry('Unknown', ''),
      )
      .key;
}
