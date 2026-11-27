import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_language.dart';

class QaDeviceLogin extends StatelessWidget {
  const QaDeviceLogin({super.key});

  static const bool _enabled = bool.fromEnvironment('TONGYEOK_DEVICE_QA_LOGIN');
  static const String _host = String.fromEnvironment(
    'TONGYEOK_QA_PREVIEW_HOST',
  );
  static const String _koUid = String.fromEnvironment('TONGYEOK_DEV_KO_UID');
  static const String _mnUid = String.fromEnvironment('TONGYEOK_DEV_MN_UID');

  bool get _visible =>
      _enabled &&
      kIsWeb &&
      _koUid.isNotEmpty &&
      _mnUid.isNotEmpty &&
      _host.isNotEmpty &&
      Uri.base.scheme == 'https' &&
      Uri.base.host == _host;

  bool get _mn => AppLanguage.instance.displayCode == 'mn';

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      children: [
        OutlinedButton(
          onPressed: () => _open(context, 'ko'),
          child: Text(_mn ? 'Солонгос хяналт' : '한국어 검수'),
        ),
        OutlinedButton(
          onPressed: () => _open(context, 'mn'),
          child: Text(_mn ? 'Монгол хяналт' : '몽골어 검수'),
        ),
      ],
    );
  }

  Future<void> _open(BuildContext context, String role) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => _QaPasswordDialog(
            role: role,
            mn: _mn,
            koUid: _koUid,
            mnUid: _mnUid,
          ),
    );
  }
}

class _QaPasswordDialog extends StatefulWidget {
  const _QaPasswordDialog({
    required this.role,
    required this.mn,
    required this.koUid,
    required this.mnUid,
  });

  final String role;
  final bool mn;
  final String koUid;
  final String mnUid;

  @override
  State<_QaPasswordDialog> createState() => _QaPasswordDialogState();
}

class _QaPasswordDialogState extends State<_QaPasswordDialog> {
  final TextEditingController _password = TextEditingController();
  bool _busy = false;
  bool _error = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  String get _email =>
      widget.role == 'ko'
          ? 'qa-ko-2010@dev.tongyeok.invalid'
          : 'qa-mn-2010@dev.tongyeok.invalid';

  Future<void> _connect() async {
    if (_busy) return;
    final nav = Navigator.of(context, rootNavigator: true);
    final uid = widget.role == 'ko' ? widget.koUid : widget.mnUid;
    setState(() {
      _busy = true;
      _error = false;
    });
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email,
        password: _password.text,
      );
      if (uid.isNotEmpty && cred.user?.uid == uid) {
        await AppLanguage.instance.select(widget.role);
        if (!mounted) return;
        nav.pushNamedAndRemoveUntil('/recentConversations', (_) => false);
        return;
      }
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mn = widget.mn;
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _password,
            autofocus: true,
            obscureText: true,
            enabled: !_busy,
            decoration: InputDecoration(labelText: mn ? 'Нууц үг' : '비밀번호'),
            onSubmitted: (_) => _connect(),
          ),
          if (_error) ...[
            const SizedBox(height: 8),
            Text(
              mn ? 'Алдаа гарлаа. Дахин оролдоно уу.' : '오류가 발생했습니다. 다시 시도하세요.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(mn ? 'Болих' : '취소'),
        ),
        FilledButton(
          onPressed: _busy ? null : _connect,
          child:
              _busy
                  ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : Text(mn ? 'Холбох' : '연결'),
        ),
      ],
    );
  }
}
