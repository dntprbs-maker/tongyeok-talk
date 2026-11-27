import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('tongyeokComposeReferralSms')
external JSPromise<JSBoolean> _compose(String phone, String code);

@JS('tongyeokComposeGuestSms')
external JSPromise<JSBoolean> _composeGuest(String link);

bool get referralSmsAvailable =>
    globalContext.has('tongyeokComposeReferralSms');
bool get guestSmsAvailable => globalContext.has('tongyeokComposeGuestSms');

Future<bool> composeReferralSms(String phone, String code) async =>
    (await _compose(phone, code).toDart).toDart;

Future<bool> composeGuestSms(String link) async =>
    (await _composeGuest(link).toDart).toDart;
