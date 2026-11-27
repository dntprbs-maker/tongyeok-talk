final referralEndpoint = Uri.https(
  'asia-northeast3-tongyeok-talk-lab-20261024.cloudfunctions.net',
  '/rewardApi/referrals',
);

bool isReferralCode(String code) => RegExp(r'^[A-F0-9]{16}$').hasMatch(code);

bool isReferralPhone(String phone) =>
    RegExp(r'^\+?[0-9]{8,15}$').hasMatch(phone);

String? guestSmsMessage(String link) {
  final uri = Uri.tryParse(link);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'tongyeok-talk-lab-20261024.web.app' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.path != '/guest' ||
      !RegExp(r'^room=[a-f0-9]{40}$').hasMatch(uri.query) ||
      !RegExp(r'^invite=[a-f0-9]{64}$').hasMatch(uri.fragment)) {
    return null;
  }
  return '통역톡 비회원 대화 초대입니다. 아래 링크를 열고 이름을 입력한 뒤, '
      '동의하고 채팅창에 글을 써 주세요.\n$link';
}

String referralMessage(String code) {
  final link = referralEndpoint.replace(
    path: '/rewardApi/invite',
    queryParameters: {'ref': code},
  );
  return '통역톡 · Орчуулагч Ток\n$link';
}
