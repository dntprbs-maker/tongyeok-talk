bool get referralSmsAvailable => false;
bool get guestSmsAvailable => false;

Future<bool> composeReferralSms(String phone, String code) async => false;
Future<bool> composeGuestSms(String link) async => false;

Future<bool> composeLocalizedReferralSms(
  String phone,
  String code,
  String language,
) async => false;
