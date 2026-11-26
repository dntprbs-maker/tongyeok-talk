import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('tongyeokComposeReferralSms')
external JSPromise<JSBoolean> _compose(String phone, String code);

bool get referralSmsAvailable =>
    globalContext.has('tongyeokComposeReferralSms');

Future<bool> composeReferralSms(String phone, String code) async =>
    (await _compose(phone, code).toDart).toDart;
