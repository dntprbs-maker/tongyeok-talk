import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'app_language.dart';

class MessageBubble extends StatelessWidget {
  final String senderId, currentUserId, originalText, translatedText;
  final DateTime timestamp;
  final String? sourceLang, targetLang;
  final String translationStatus;
  final bool sent, read;
  final VoidCallback? onRetry;
  const MessageBubble({
    super.key,
    required this.senderId,
    required this.currentUserId,
    required this.originalText,
    required this.translatedText,
    required this.timestamp,
    this.sourceLang,
    this.targetLang,
    this.translationStatus = 'pending',
    this.sent = true,
    this.read = false,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final mine = senderId == currentUserId;
    final primary = AppLanguage.instance.code;
    final secondary = primary == 'ko' ? 'mn' : 'ko';
    final values = <String, String>{sourceLang ?? 'ko': originalText};
    if (translationStatus == 'done' && targetLang != null) {
      values[targetLang!] = translatedText;
    }
    final color = mine ? Colors.white : Colors.black87;
    Widget line(String language) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${tr(context, language)}${language == sourceLang ? ' · ${tr(context, 'original')}' : ''}',
          style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.75)),
        ),
        const SizedBox(height: 3),
        Text(
          values[language] ??
              tr(
                context,
                translationStatus == 'failed'
                    ? 'translationFailed'
                    : 'translationPending',
              ),
          style: TextStyle(fontSize: 16, height: 1.4, color: color),
        ),
      ],
    );
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth:
              MediaQuery.sizeOf(context).width < 600
                  ? MediaQuery.sizeOf(context).width * 0.84
                  : 500,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: mine ? const Color(0xFF5268D8) : const Color(0xFFF1F1F1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              line(primary),
              const Divider(),
              line(secondary),
              if (translationStatus != 'done' && onRetry != null)
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(foregroundColor: color),
                  child: Text(tr(context, 'retryTranslation')),
                ),
              const SizedBox(height: 6),
              Text(
                '${DateFormat.Hm(AppLanguage.instance.code).format(timestamp)}${mine ? ' · ${tr(context, !sent
                        ? 'sending'
                        : read
                        ? 'read'
                        : 'sent')}' : ''}',
                style: TextStyle(
                  fontSize: 11,
                  color: color.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
