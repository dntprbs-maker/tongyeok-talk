final referralEndpoint = Uri.https(
  'asia-northeast3-tongyeok-talk-lab-20261024.cloudfunctions.net',
  '/rewardApi/referrals',
);

bool isReferralCode(String code) => RegExp(r'^[A-F0-9]{16}$').hasMatch(code);

bool isReferralPhone(String phone) =>
    RegExp(r'^\+?[0-9]{8,15}$').hasMatch(phone);

Uri friendReferralLink(String code, String language, {String? platform}) =>
    Uri.https(
      const String.fromEnvironment(
        'TONGYEOK_REFERRAL_INVITE_HOST',
        defaultValue: 'tongyeok-talk-lab-20261024.web.app',
      ),
      '/i',
      {'r': code, 'l': language, if (platform != null) 'p': platform},
    );

String referralMessage(String code, {String? language}) {
  if (language != null) {
    final android = friendReferralLink(code, language, platform: 'a');
    final ios = friendReferralLink(code, language, platform: 'i');
    return language == 'mn'
        ? 'Орчуулагч Ток-д урьж байна!\nАппыг суулгаад бүртгүүлээрэй.\n\n'
            'Android · Google Play\n$android\n\niPhone · App Store\n$ios'
        : '통역톡에 초대합니다!\n휴대폰에 맞는 링크에서 앱을 설치하고 가입해 주세요.\n\n'
            '안드로이드 · Google Play\n$android\n\n아이폰 · App Store\n$ios';
  }
  final link = referralEndpoint.replace(
    path: '/rewardApi/invite',
    queryParameters: {'ref': code},
  );
  return '통역톡 · Орчуулагч Ток\n$link';
}
