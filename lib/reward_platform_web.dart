import 'dart:js_interop';

@JS('tongyeokNativeRewardSupported')
external JSBoolean? get _supported;
@JS('tongyeokNativeRewardTestMode')
external JSBoolean? get _testMode;
@JS('tongyeokRewardPrepare')
external JSPromise<JSString> _prepare(JSString uid);
@JS('tongyeokRewardShow')
external JSPromise<JSString> _show(
  JSString uid,
  JSString sessionId,
  JSString adUnitId,
  JSBoolean testAds,
);
@JS('tongyeokRewardPrivacy')
external JSPromise<JSString> _privacy(JSString uid);
@JS('window.addEventListener')
external void _addListener(JSString name, JSFunction listener);
@JS('window.removeEventListener')
external void _removeListener(JSString name, JSFunction listener);

bool get supported => _supported?.toDart == true;
bool get testMode => _testMode?.toDart ?? true;
void Function() listenAvailability(void Function() callback) {
  final listener =
      ((JSAny? event) {
        callback();
      }).toJS;
  final name = 'tongyeok-native-reward-ready'.toJS;
  _addListener(name, listener);
  return () => _removeListener(name, listener);
}

Future<void> prepare(String uid) async {
  if (!supported) throw StateError('adUnavailable');
  final result = (await _prepare(uid.toJS).toDart).toDart;
  if (result != 'ready') throw StateError('adConsentFailed');
}

Future<bool> show(
  String uid,
  String sessionId,
  String adUnitId,
  bool testAds,
) async {
  if (!supported) throw StateError('adUnavailable');
  final result =
      (await _show(
            uid.toJS,
            sessionId.toJS,
            adUnitId.toJS,
            testAds.toJS,
          ).toDart)
          .toDart;
  if (result != 'earned' && result != 'dismissed') {
    throw StateError('adLoadFailed');
  }
  return result == 'earned';
}

Future<void> privacy(String uid) async {
  if (!supported) throw StateError('adUnavailable');
  await _privacy(uid.toJS).toDart;
}
