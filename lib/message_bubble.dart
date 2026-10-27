import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'app_language.dart';
import 'chat_display_preferences.dart';

class MessageBubble extends StatefulWidget {
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
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _expanded = false;
  @override
  void initState() {
    super.initState();
    ChatDisplayPreferences.instance.addListener(_resetExpansion);
  }

  void _resetExpansion() => setState(() => _expanded = false);

  @override
  void dispose() {
    ChatDisplayPreferences.instance.removeListener(_resetExpansion);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.originalText != widget.originalText ||
        oldWidget.sourceLang != widget.sourceLang) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = widget.senderId == widget.currentUserId;
    final primary = LanguageScope.of(context).code;
    final secondary = primary == 'ko' ? 'mn' : 'ko';
    final source = widget.sourceLang ?? 'ko';
    final values = <String, String>{source: widget.originalText};
    if (widget.translationStatus == 'done' &&
        widget.targetLang != null &&
        widget.translatedText.isNotEmpty) {
      values[widget.targetLang!] = widget.translatedText;
    }
    final primaryReady = values[primary] != null;
    final always = ChatDisplayPreferences.instance.showOtherLanguage;
    // Never hide the only available original while waiting for translation.
    final showSecondary = always || _expanded || !primaryReady;
    final color = mine ? Colors.white : const Color(0xFF172635);
    final muted =
        mine ? Colors.white.withValues(alpha: 0.8) : const Color(0xFF4C5E6E);

    Widget line(String language, {bool main = false}) => Text.rich(
      TextSpan(
        children: [
          if (!main)
            TextSpan(
              text:
                  '${tr(context, language)}${language == source ? ' · ${tr(context, 'original')}' : ''}  ',
              style: TextStyle(fontSize: 10, color: muted),
            ),
          TextSpan(
            text:
                values[language] ??
                tr(
                  context,
                  widget.translationStatus == 'failed'
                      ? 'translationFailed'
                      : 'translationPending',
                ),
          ),
        ],
      ),
      textWidthBasis: TextWidthBasis.longestLine,
      style: TextStyle(
        fontSize: main ? 16 : 14,
        height: 1.3,
        color: main ? color : muted,
      ),
    );

    final bubble = Container(
      key: const ValueKey('message-surface'),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: mine ? const Color(0xFF5268D8) : Colors.white,
        border: mine ? null : Border.all(color: const Color(0xFFC2CFDE)),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(14),
          topRight: const Radius.circular(14),
          bottomLeft: Radius.circular(mine ? 14 : 4),
          bottomRight: Radius.circular(mine ? 4 : 14),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          line(primary, main: true),
          if (showSecondary) ...[const SizedBox(height: 5), line(secondary)],
          if (widget.translationStatus != 'done' && widget.onRetry != null)
            TextButton(
              onPressed: widget.onRetry,
              style: TextButton.styleFrom(foregroundColor: color),
              child: Text(tr(context, 'retryTranslation')),
            ),
        ],
      ),
    );
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth:
                MediaQuery.sizeOf(context).width < 600
                    ? MediaQuery.sizeOf(context).width * 0.87
                    : 490,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              bubble,
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: mine ? WrapAlignment.end : WrapAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 3, right: 3),
                    child: Text(
                      '${DateFormat('yyyy.MM.dd HH:mm', primary).format(widget.timestamp)}${mine ? ' · ${tr(context, !widget.sent
                              ? 'sending'
                              : widget.read
                              ? 'read'
                              : 'sent')}' : ''}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF465666),
                      ),
                    ),
                  ),
                  if (!always && primaryReady)
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _expanded = !_expanded),
                      icon: Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF273F60),
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF6B819D)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: const Size(48, 32),
                        tapTargetSize: MaterialTapTargetSize.padded,
                        alignment: Alignment.centerLeft,
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      label: Text(
                        tr(
                          context,
                          _expanded
                              ? 'hideOtherLanguage'
                              : secondary == source
                              ? 'showOriginal'
                              : 'showTranslation',
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
