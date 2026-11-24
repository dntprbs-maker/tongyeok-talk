bool get nativeSocialLoginAvailable => false;

Future<String> requestNativeSocialLogin(
  String provider, {
  String? legacyToken,
  String? expectedUid,
}) => Future.error(UnsupportedError('Native social login bridge unavailable'));
