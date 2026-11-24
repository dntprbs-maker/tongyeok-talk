import 'dart:js_interop';

@JS('tongyeokSocialLoginAvailable')
external JSBoolean? get _available;

@JS('tongyeokSocialLogin')
external JSPromise<JSString> _signIn(
  JSString provider,
  JSString? legacyToken,
  JSString? expectedUid,
);

bool get nativeSocialLoginAvailable => _available?.toDart == true;

Future<String> requestNativeSocialLogin(
  String provider, {
  String? legacyToken,
  String? expectedUid,
}) async => (await _signIn(
  provider.toJS,
  legacyToken?.toJS,
  expectedUid?.toJS,
).toDart).toDart;
