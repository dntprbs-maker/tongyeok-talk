import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_language.dart';
import 'contact_names_platform.dart';
import 'referral_invite.dart';
import 'referral_sms_stub.dart'
    if (dart.library.js_interop) 'referral_sms_web.dart'
    as sms;

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

String referralLabel(BuildContext context) => tr(context, 'friendInvite');

TextEditingValue _formatInvitePhone(
  TextEditingValue oldValue,
  TextEditingValue newValue,
) {
  final input = newValue.text;
  if (!newValue.composing.isCollapsed ||
      !RegExp(r'^010[0-9-]*$').hasMatch(input)) {
    return newValue;
  }
  final digits = input.replaceAll('-', '');
  if (digits.length <= 3 || digits.length > 11) return newValue;
  final formatted = digits.length <= 7
      ? '010-${digits.substring(3)}'
      : '010-${digits.substring(3, 7)}-${digits.substring(7)}';
  if (formatted == input || !newValue.selection.isValid) return newValue;
  int offset(int cursor) {
    final before = input.substring(0, cursor).replaceAll('-', '').length;
    if (before >= digits.length) return formatted.length;
    return before + (before > 3 ? 1 : 0) + (before > 7 ? 1 : 0);
  }

  return TextEditingValue(
    text: formatted,
    selection: TextSelection(
      baseOffset: offset(newValue.selection.baseOffset),
      extentOffset: offset(newValue.selection.extentOffset),
    ),
  );
}

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

final _shownReferralAnnouncements = <String>{};

Future<void> showReferralAnnouncement(BuildContext context, String uid) async {
  if (!context.mounted ||
      !(ModalRoute.of(context)?.isCurrent ?? false) ||
      !_shownReferralAnnouncements.add(uid)) {
    return;
  }
  final policy = referralRequest('status').then<bool>(
    (status) => status['waitDays'] == 0,
    onError: (Object _) => false,
  );
  final details = await showDialog<bool>(
    context: context,
    builder: (dialog) {
      final mn = LanguageScope.of(dialog).code == 'mn';
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
                  child: FutureBuilder<bool>(
                    future: policy,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const SizedBox(height: 48);
                      }
                      if (snapshot.data == true) {
                        return Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              Image.asset(
                                'assets/images/reward-ticket.png',
                                width: 144,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                mn
                                    ? '5 хоногийн эрх (эсвэл 500 өгүүлбэрийн орчуулгын эрх)'
                                    : '5일 이용권 (또는 500문장 번역권)',
                              ),
                              const SizedBox(height: 8),
                              Text(
                                mn
                                    ? 'Найз тань бүртгүүлээд аппыг 10-аас доошгүй өдөр ашиглавал олгоно.'
                                    : '친구가 가입한 뒤 10일 이상 통역톡을 사용하시면 드려요.',
                              ),
                            ],
                          ),
                        );
                      }
                      return Image.asset(
                        mn
                            ? 'assets/images/referral-announcement-mn.png'
                            : 'assets/images/referral-announcement.png',
                        fit: BoxFit.contain,
                        semanticLabel: referralRules(dialog),
                      );
                    },
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
    await showReferralInviteDialog(context);
  }
}

Future<void> showReferralInviteDialog(BuildContext context) => showDialog<void>(
  context: context,
  barrierColor: const Color(0xc7000000),
  builder: (_) => const ReferralScreen(),
);

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key, this.loadStatus});

  final Future<Map<String, dynamic>> Function()? loadStatus;

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

enum _InviteStep { method, language, qr, sms }

class _ReferralScreenState extends State<ReferralScreen> {
  late Future<Map<String, dynamic>> _status = _loadStatus();
  final _phone = TextEditingController();
  final _phoneFocus = FocusNode();
  _InviteStep _step = _InviteStep.method;
  _InviteStep _method = _InviteStep.qr;
  String? _recipientLanguage;
  bool _busy = false;
  bool _offerCopy = false;
  String? _error;

  Future<Map<String, dynamic>> _loadStatus() =>
      widget.loadStatus?.call() ?? referralRequest('status');

  @override
  void dispose() {
    _phone.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  String _text(String ko, String mn) =>
      LanguageScope.of(context).code == 'mn' ? mn : ko;

  void _chooseMethod(_InviteStep method) {
    final sender = LanguageScope.of(context).code;
    setState(() {
      _method = method;
      _recipientLanguage = sender == 'mn' ? 'ko' : 'mn';
      _step = _InviteStep.language;
    });
  }

  void _back() {
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _offerCopy = false;
      _step = _step == _InviteStep.language
          ? _InviteStep.method
          : _InviteStep.language;
    });
  }

  Future<void> _pickPhone() async {
    if (kIsWeb && !androidContactsAvailable) {
      _contactError();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picked = kIsWeb
          ? await requestAndroidContacts({'op': 'pickPhone'})
          : await const MethodChannel('tongyeok/contacts')
                .invokeMethod<String>('pickPhone');
      if (picked is String && mounted) {
        final number = picked.replaceAll(RegExp(r'[\s().-]'), '');
        final localNumber = number.startsWith('+8210')
            ? '0${number.substring(3)}'
            : number;
        if (isReferralPhone(localNumber)) {
          final value = TextEditingValue(
            text: localNumber,
            selection: TextSelection.collapsed(offset: localNumber.length),
          );
          _phone.value = _formatInvitePhone(TextEditingValue.empty, value);
        } else {
          setState(
            () =>
                _error = _text('전화번호를 확인해 주세요.', 'Утасны дугаарыг шалгана уу.'),
          );
        }
      }
    } on PlatformException {
      if (mounted) _contactError();
    } on MissingPluginException {
      if (mounted) _contactError();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _contactError() => setState(
    () => _error = _text(
      '연락처를 열 수 없어요. 번호를 직접 입력해 주세요.',
      'Харилцагчдыг нээж чадсангүй. Дугаарыг гараар оруулна уу.',
    ),
  );

  Future<void> _compose(String code) async {
    final number = _phone.text.replaceAll(RegExp(r'[\s().-]'), '');
    if (!isReferralPhone(number)) {
      setState(
        () => _error = _text('전화번호를 확인해 주세요.', 'Утасны дугаарыг шалгана уу.'),
      );
      _phoneFocus.requestFocus();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _offerCopy = false;
    });
    final language = _recipientLanguage!;
    var opened = false;
    try {
      if (kIsWeb) {
        opened = await sms.composeLocalizedReferralSms(number, code, language);
      } else {
        await const MethodChannel('tongyeok/invite').invokeMethod<void>(
          'composeSms',
          {'phone': number, 'body': referralMessage(code, language: language)},
        );
        opened = true;
      }
    } on PlatformException {
      opened = false;
    } on MissingPluginException {
      opened = false;
    } finally {
      if (mounted)
        setState(() {
          _busy = false;
          if (!opened) {
            _error = _text('문자 앱을 열 수 없어요.', 'Мессежийн аппыг нээж чадсангүй.');
            _offerCopy = true;
          }
        });
    }
  }

  Future<void> _copy(String code) async {
    final body = referralMessage(code, language: _recipientLanguage);
    try {
      await Clipboard.setData(ClipboardData(text: body));
      if (mounted)
        setState(
          () => _error = _text(
            '복사했어요. 문자 앱에 붙여 넣어 주세요.',
            'Хууллаа. Мессежийн аппад буулгана уу.',
          ),
        );
    } on PlatformException {
      if (mounted)
        setState(() => _error = _text('복사할 수 없어요.', 'Хуулж чадсангүй.'));
    }
  }

  Widget _methodCard({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool primary = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 112,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: primary ? colors.primary : colors.secondaryContainer,
          foregroundColor: primary
              ? colors.onPrimary
              : colors.onSecondaryContainer,
          padding: const EdgeInsets.all(8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 26),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  List<Widget> _methods(Map<String, dynamic> data) {
    final theme = Theme.of(context);
    final waitDays = data['waitDays'] is int ? data['waitDays'] as int : 30;
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              _text(
                '지급 대기 ${data['pending']}건',
                'Хүлээгдэж буй ${data['pending']}',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xff805011)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _text(
                '지급 완료 ${data['rewarded']}건',
                'Олгосон ${data['rewarded']}',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xff126557)),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      const Divider(),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: _methodCard(
              icon: Icons.qr_code,
              primary: true,
              label: _text('QR 코드로\n초대하기', 'QR кодоор\nурих'),
              onPressed: () => _chooseMethod(_InviteStep.qr),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _methodCard(
              icon: Icons.sms_outlined,
              label: _text('문자로\n초대하기', 'Мессежээр\nурих'),
              onPressed: () => _chooseMethod(_InviteStep.sms),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withAlpha(90),
          borderRadius: BorderRadius.circular(18),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              right: 5,
              top: 8,
              child: Opacity(
                opacity: .14,
                child: Image.asset(
                  'assets/images/reward-ticket.png',
                  width: 124,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _text('보상', 'Урамшуулал'),
                    style: theme.textTheme.labelLarge,
                  ),
                  Text(
                    _text('5일 이용권', '5 хоногийн эрх'),
                    style: theme.textTheme.headlineSmall,
                  ),
                  Text(
                    _text(
                      '(또는 500문장 번역권)',
                      '(эсвэл 500 өгүүлбэрийн орчуулгын эрх)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    waitDays == 0
                        ? _text(
                            '친구가 가입한 뒤 10일 이상 통역톡을 사용하시면 드려요.',
                            'Найз тань бүртгүүлээд аппыг 10-аас доошгүй өдөр ашиглавал олгоно.',
                          )
                        : _text(
                            '친구가 가입 후 10일 이상 사용하면, 가입 ${waitDays}일 뒤 보상을 드려요.',
                            'Найз тань аппыг 10-аас доошгүй өдөр ашиглавал бүртгүүлснээс хойш $waitDays хоногийн дараа олгоно.',
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _languages() => [
    Text(
      _text('받으시는 분의 언어를 선택해 주세요', 'Хүлээн авагчийн хэлийг сонгоно уу'),
      style: Theme.of(context).textTheme.titleMedium,
    ),
    const SizedBox(height: 16),
    Row(
      children: [
        Expanded(child: _languageButton('ko', _text('한국어', 'Солонгос хэл'))),
        const SizedBox(width: 10),
        Expanded(child: _languageButton('mn', _text('몽골어', 'Монгол хэл'))),
      ],
    ),
  ];

  Widget _languageButton(String language, String label) {
    void choose() => setState(() {
      _recipientLanguage = language;
      _step = _method;
    });
    final child = Text(label, textAlign: TextAlign.center);
    return Semantics(
      selected: _recipientLanguage == language,
      child: SizedBox(
        height: 56,
        child: _recipientLanguage == language
            ? FilledButton(onPressed: choose, child: child)
            : OutlinedButton(onPressed: choose, child: child),
      ),
    );
  }

  List<Widget> _qr(String code) {
    final mn = _recipientLanguage == 'mn';
    return [
      Center(
        child: QrImageView(
          data: friendReferralLink(code, _recipientLanguage!).toString(),
          size: 214,
          backgroundColor: Colors.white,
        ),
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mn ? 'QR кодыг камераар уншуулна уу' : '카메라로 QR을 찍어 주세요',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              mn
                  ? 'Нээгдсэн хуудсаас утсандаа тохирох дэлгүүрийг сонгож, аппыг суулгаад бүртгүүлнэ үү.'
                  : '열린 화면에서 휴대폰에 맞는 스토어를 선택해 통역톡을 설치하고 가입해 주세요.',
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _sms(String code) => [
    Text(
      _text('초대할 친구의 번호를 선택해 주세요.', 'Урих хүний утасны дугаарыг сонгоно уу.'),
    ),
    const SizedBox(height: 12),
    OutlinedButton.icon(
      onPressed: _busy ? null : _pickPhone,
      icon: const Icon(Icons.contacts_outlined),
      label: Text(_text('연락처에서 찾기', 'Харилцагчаас сонгох')),
    ),
    const SizedBox(height: 6),
    OutlinedButton.icon(
      onPressed: _busy ? null : _phoneFocus.requestFocus,
      icon: const Icon(Icons.dialpad),
      label: Text(_text('전화번호 직접 입력', 'Дугаарыг гараар оруулах')),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: _phone,
      focusNode: _phoneFocus,
      enabled: !_busy,
      keyboardType: TextInputType.phone,
      inputFormatters: [TextInputFormatter.withFunction(_formatInvitePhone)],
      maxLength: 18,
      decoration: InputDecoration(
        labelText: _text('전화번호', 'Утасны дугаар'),
        hintText: '010-0000-0001',
        counterText: '',
      ),
    ),
    const SizedBox(height: 12),
    FilledButton(
      onPressed: _busy ? null : () => _compose(code),
      child: Text(_text('초대하기', 'Урих')),
    ),
    if (_error != null)
      Text(_error!, style: Theme.of(context).textTheme.bodySmall),
    if (_offerCopy)
      TextButton(
        onPressed: () => _copy(code),
        child: Text(_text('초대 문자 복사', 'Урилгын зурвасыг хуулах')),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final title = switch (_step) {
      _InviteStep.method => referralLabel(context),
      _InviteStep.language => _text('받는 분의 언어', 'Хүлээн авагчийн хэл'),
      _InviteStep.qr => _text('QR 코드로 초대', 'QR кодоор урих'),
      _InviteStep.sms => _text('문자로 초대', 'Мессежээр урих'),
    };
    return PopScope(
      canPop: _step == _InviteStep.method,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _back();
      },
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (_step != _InviteStep.method)
                      IconButton(
                        onPressed: _busy ? null : _back,
                        tooltip: MaterialLocalizations.of(context)
                            .backButtonTooltip,
                        icon: const Icon(Icons.arrow_back),
                      ),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                      tooltip: tr(context, 'chatCreditClose'),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 12),
                    child: FutureBuilder(
                      future: _status,
                      builder: (context, snapshot) {
                        final data = snapshot.data;
                        final code = data?['code'];
                        final Widget body;
                        if (snapshot.hasError ||
                            (data != null &&
                                (code is! String || !isReferralCode(code)))) {
                          body = OutlinedButton(
                            onPressed: () =>
                                setState(() => _status = _loadStatus()),
                            child: Text(_text('다시 시도', 'Дахин оролдох')),
                          );
                        } else if (data == null || code is! String) {
                          body = const LinearProgressIndicator();
                        } else {
                          body = Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: switch (_step) {
                              _InviteStep.method => _methods(data),
                              _InviteStep.language => _languages(),
                              _InviteStep.qr => _qr(code),
                              _InviteStep.sms => _sms(code),
                            },
                          );
                        }
                        return body;
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
