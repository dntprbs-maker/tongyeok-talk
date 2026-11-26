final referralEndpoint = Uri.https(
  'asia-northeast3-tongyeok-talk-lab-20261024.cloudfunctions.net',
  '/rewardApi/referrals',
);

bool isReferralCode(String code) => RegExp(r'^[A-F0-9]{16}$').hasMatch(code);

bool isReferralPhone(String phone) =>
    RegExp(r'^\+?[0-9]{8,15}$').hasMatch(phone);

String referralMessage(String code) {
  final link = referralEndpoint.replace(
    path: '/rewardApi/invite',
    queryParameters: {'ref': code},
  );
  return '통역톡 · Орчуулагч Ток\n$link';
}
