import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_language.dart';

const _referralEndpoint =
    'https://asia-northeast3-tongyeok-talk-lab-20261024.cloudfunctions.net/rewardApi/referrals';
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
    if (code == null || !RegExp(r'^[A-F0-9]{16}$').hasMatch(code)) return;
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
        Uri.parse('$_referralEndpoint/$action'),
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

String referralLabel(BuildContext context) =>
    LanguageScope.of(context).code == 'mn' ? 'Урилгын урамшуулал' : '추천 보상';

String referralRegistrationError(BuildContext context, String error) {
  final mn = LanguageScope.of(context).code == 'mn';
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
    LanguageScope.of(context).code == 'mn'
        ? 'Урилгаар бүртгүүлсэн хүн 30 хоногийн дараа, 10 өөр өдөр зурвас илгээсэн бол түүнийг урьсан гишүүнд урамшуулал автоматаар олгоно. Багийн ахлагчид 5 хоног, багийн гишүүнд 500 өгүүлбэрийн орчуулгын эрх олгоно.'
        : '소개받은 사람이 가입 후 30일이 지나고 서로 다른 10일에 메시지를 보내면, 소개한 팀장에게 이용권 5일, 소개한 팀원에게 번역권 500문장을 자동 지급해요.';

Future<void> showReferralAnnouncement(BuildContext context, String uid) async {
  final prefs = await SharedPreferences.getInstance();
  final key = 'referral_announcement_v2_$uid';
  if (!context.mounted || prefs.getBool(key) == true) return;
  await prefs.setBool(key, true);
  if (!context.mounted) return;
  final details = await showDialog<bool>(
    context: context,
    builder: (dialog) {
      final mn = LanguageScope.of(dialog).code == 'mn';
      return AlertDialog(
        title: Text(referralLabel(dialog)),
        content: Text(referralRules(dialog)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(mn ? 'Хаах' : '닫기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(mn ? 'Урилга харах' : '문자로 초대하기'),
          ),
        ],
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
    if (!RegExp(r'^\+?[0-9]{8,15}$').hasMatch(number)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mn ? 'Утасны дугаараа шалгана уу.' : '전화번호를 확인해 주세요.'),
        ),
      );
      return;
    }

    final link = Uri.parse(
      _referralEndpoint,
    ).replace(path: '/rewardApi/invite', queryParameters: {'ref': code});
    setState(() => _sending = true);
    try {
      await const MethodChannel('tongyeok/invite').invokeMethod<void>(
        'composeSms',
        {'phone': number, 'body': '통역톡 · Орчуулагч Ток\n$link'},
      );
    } on PlatformException catch (_) {
      if (mounted) _showSmsUnavailable(mn);
    } on MissingPluginException catch (_) {
      if (mounted) _showSmsUnavailable(mn);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
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
    final mn = LanguageScope.of(context).code == 'mn';
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
                  const SizedBox(height: 12),
                  Text(
                    mn
                        ? 'Мессежийн аппад зурвасаа шалгаад илгээнэ үү.'
                        : '소개받은 사람이 문자 앱에서 내용을 확인하고 전송해 주세요.',
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
