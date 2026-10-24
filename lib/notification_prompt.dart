import 'package:flutter/material.dart';
import 'app_language.dart';
import 'push_service.dart';

class NotificationPrompt extends StatefulWidget {
  final Future<String> Function()? readState, enable;
  const NotificationPrompt({super.key, this.readState, this.enable});
  @override
  State<NotificationPrompt> createState() => NotificationPromptState();
}

class NotificationPromptState extends State<NotificationPrompt>
    with WidgetsBindingObserver {
  static bool launchWarningShown = false;
  String? _status;
  bool _busy = false, _dismissed = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  Future<void> refresh() async {
    try {
      final value = await (widget.readState ?? PushService.state)();
      if (mounted) setState(() => _status = value);
      if (mounted &&
          value != 'enabled' &&
          value != 'unsupported' &&
          !launchWarningShown) {
        launchWarningShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(tr(context, 'pushLaunchWarning'))),
            );
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _status = 'off');
    }
  }

  Future<void> _enable() async {
    setState(() => _busy = true);
    try {
      final value = await (widget.enable ?? PushService.enable)();
      if (mounted) {
        setState(() => _status = value);
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                context,
                value == 'enabled'
                    ? 'pushEnabled'
                    : value == 'denied'
                    ? 'pushDenied'
                    : value == 'unsupported'
                    ? 'pushUnsupported'
                    : 'pushOff',
              ),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(tr(context, 'pushFailed'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_status == null ||
        _status == 'enabled' ||
        _status == 'unsupported' ||
        _dismissed) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF1FF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.notifications_active_outlined,
            color: Color(0xFF3346B8),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, 'notificationPromptTitle'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  tr(
                    context,
                    _status == 'denied'
                        ? 'pushDenied'
                        : 'notificationPromptBody',
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      onPressed: _busy ? null : _enable,
                      child: Text(tr(context, 'notificationPromptEnable')),
                    ),
                    TextButton(
                      onPressed:
                          _busy
                              ? null
                              : () => setState(() => _dismissed = true),
                      child: Text(tr(context, 'later')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
