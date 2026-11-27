import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('tongyeokComposeLocalizedReferralSms')
external JSPromise<JSBoolean> _composeLocalized(
  String phone,
  String code,
  String language,
);

Future<bool> composeLocalizedReferralSms(
  String phone,
  String code,
  String language,
) async =>
    globalContext.has('tongyeokComposeLocalizedReferralSms') &&
    (await _composeLocalized(phone, code, language).toDart).toDart;
