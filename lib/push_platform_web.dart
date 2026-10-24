import 'dart:js_interop';

@JS('tongyeokPushEnable')
external JSPromise<JSString> _enable(JSString uid);
@JS('tongyeokPushDisable')
external JSPromise<JSString> _disable(JSString uid);
@JS('tongyeokPushState')
external JSPromise<JSString> _state(JSString uid);
Future<String> enablePush(String uid) async =>
    (await _enable(uid.toJS).toDart).toDart;
Future<String> disablePush(String uid) async =>
    (await _disable(uid.toJS).toDart).toDart;
Future<String> pushState(String uid) async =>
    (await _state(uid.toJS).toDart).toDart;
