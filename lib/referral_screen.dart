import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_language.dart';
import 'referral_invite.dart';
import 'referral_sms_stub.dart'
    if (dart.library.js_interop) 'referral_sms_web.dart'
    as sms;

const _pendingReferralKey = 'pending_referral';
String? _pendingLinkCode;

Future<void> initializeReferralLinks() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
  final appLinks = AppLinks();
  final prefs = await SharedPreferences.getInstance();
  _pendingLinkCode = prefs.getString(_pendingReferralKey);
  Future<void> capture(Uri? uri) async {
    if (uri?.scheme != 'tongyeoktalk' || uri?.host != 'referral') return;
    final code = uri?.queryParameters['ref'];
    if (code == null || !isReferralCode(code)) return;
    _pendingLinkCode = code;
    await prefs.setString(_pendingReferralKey, code);
  }

  appLinks.uriLinkStream.listen(capture);
  await capture(await appLinks.getInitialLink());
}

Future<String?> pendingReferral() async => _pendingLinkCode;

Future<void> clearReferral() async {
  _pendingLinkCode = null;
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_pendingReferralKey);
}

Future<Map<String, dynamic>> referralRequest(
  String action, {
  String? code,
}) async {
  final token = await FirebaseAuth.instance.currentUser!.getIdToken();
  final response = await http
      .post(
        referralEndpoint.replace(path: '${referralEndpoint.path}/$action'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({if (code != null) 'code': code}),
      )
      .timeout(const Duration(seconds: 15));
  final result =
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  if (response.statusCode != 200) {
    throw StateError(result['error'] as String? ?? 'referral_unavailable');
  }
  return result;
}

String referralLabel(BuildContext context) => tr(context, 'friendInvite');

String referralRegistrationError(BuildContext context, String error) {
  final mn = LanguageScope.of(context).displayCode == 'mn';
  return switch (error) {
    'invalid_referral_code' =>
      mn ? 'Урилгын холбоосоо шалгана уу.' : '초대 링크를 확인해 주세요.',
    'referral_role_mismatch' =>
      mn
          ? 'Багийн ахлагч, гишүүн хоёр бие биеэ урьж болно.'
          : '팀장과 팀원 사이에서 초대 링크를 사용할 수 있어요.',
    'referral_already_registered' =>
      mn ? 'Урилга аль хэдийн холбогдсон.' : '이미 초대가 연결되었어요.',
    _ => tr(context, error),
  };
}

String referralRules(BuildContext context) =>
    LanguageScope.of(context).displayCode == 'mn'
        ? 'Урилгаар бүртгүүлсэн хүн 30 хоногийн дараа, 10 өөр өдөр зурвас илгээсэн бол түүнийг урьсан гишүүнд урамшуулал автоматаар олгоно. Багийн ахлагчид 5 хоног, багийн гишүүнд 500 өгүүлбэрийн орчуулгын эрх олгоно.'
        : '소개받은 사람이 가입 후 30일이 지나고 서로 다른 10일에 메시지를 보내면, 소개한 팀장에게 이용권 5일, 소개한 팀원에게 번역권 500문장을 자동 지급해요.';

final _shownReferralAnnouncements = <String>{};

Future<void> showReferralAnnouncement(BuildContext context, String uid) async {
  if (!context.mounted ||
      !(ModalRoute.of(context)?.isCurrent ?? false) ||
      !_shownReferralAnnouncements.add(uid)) {
    return;
  }
  final details = await showDialog<bool>(
    context: context,
    builder: (dialog) {
      final mn = LanguageScope.of(dialog).displayCode == 'mn';
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: tr(dialog, 'chatCreditClose'),
                  onPressed: () => Navigator.pop(dialog),
                  icon: const Icon(Icons.close),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Image.asset(
                    mn
                        ? 'assets/images/referral-announcement-mn.png'
                        : 'assets/images/referral-announcement.png',
                    fit: BoxFit.contain,
                    semanticLabel: referralRules(dialog),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: FilledButton(
                  onPressed: () => Navigator.pop(dialog, true),
                  child: Text(tr(dialog, 'referralSmsInvite')),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (details == true && context.mounted) {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const ReferralScreen()));
  }
}

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  late Future<Map<String, dynamic>> _status = referralRequest('status');
  final _phone = TextEditingController(text: '010-');
  bool _sending = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _composeSms(bool mn, String code) async {
    final number = _phone.text.trim().replaceAll(RegExp(r'[\s().-]'), '');
    if (!isReferralPhone(number)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mn ? 'Утасны дугаараа шалгана уу.' : '전화번호를 확인해 주세요.'),
        ),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      if (kIsWeb) {
        final opened =
            sms.referralSmsAvailable &&
            await sms.composeReferralSms(number, code);
        if (!opened && mounted) _showSmsUnavailable(mn);
      } else {
        await const MethodChannel('tongyeok/invite').invokeMethod<void>(
          'composeSms',
          {'phone': number, 'body': referralMessage(code)},
        );
      }
    } catch (_) {
      if (mounted) _showSmsUnavailable(mn);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _copySms(bool mn, String code) async {
    var copied = false;
    try {
      await Clipboard.setData(ClipboardData(text: referralMessage(code)));
      copied = true;
    } on PlatformException {
      // Show a localized error if the clipboard is unavailable.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          copied
              ? (mn
                  ? 'Урилгыг хууллаа. Мессежийн аппад оруулаад илгээнэ үү.'
                  : '초대 문자를 복사했어요. 문자 앱에 붙여 넣고 보내 주세요.')
              : (mn ? 'Урилгыг хуулж чадсангүй.' : '초대 문자를 복사할 수 없어요.'),
        ),
      ),
    );
  }

  void _showSmsUnavailable(bool mn) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          mn ? 'Мессежийн аппыг нээж чадсангүй.' : '문자 앱을 열 수 없어요.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mn = LanguageScope.of(context).displayCode == 'mn';
    return Scaffold(
      appBar: AppBar(title: Text(referralLabel(context))),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(referralRules(context)),
          const SizedBox(height: 24),
          FutureBuilder(
            future: _status,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return OutlinedButton(
                  onPressed:
                      () => setState(() => _status = referralRequest('status')),
                  child: Text(mn ? 'Дахин оролдох' : '다시 시도'),
                );
              }
              final data = snapshot.data;
              if (data == null) return const LinearProgressIndicator();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _phone,
                    enabled: !_sending,
                    keyboardType: TextInputType.phone,
                    maxLength: 18,
                    decoration: InputDecoration(
                      labelText:
                          mn ? 'Урих хүний утасны дугаар' : '초대할 사람의 전화번호',
                      hintText: '010-1234-5678',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed:
                        _sending
                            ? null
                            : () => _composeSms(mn, data['code'] as String),
                    icon: const Icon(Icons.sms_outlined),
                    label: Text(mn ? 'Мессежийн апп нээх' : '문자 앱 열기'),
                  ),
                  if (kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
                    TextButton(
                      onPressed: () => _copySms(mn, data['code'] as String),
                      child: Text(mn ? 'Урилга хуулах' : '초대 문자 복사'),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    mn
                        ? 'Мессежийн аппад зурвасаа шалгаад илгээнэ үү.'
                        : '문자 내용을 확인한 뒤 직접 보내 주세요.',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    mn
                        ? 'Хүлээгдэж буй: ${data['pending']} · Олгосон: ${data['rewarded']}'
                        : '지급 대기 ${data['pending']}건 · 지급 완료 ${data['rewarded']}건',
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
