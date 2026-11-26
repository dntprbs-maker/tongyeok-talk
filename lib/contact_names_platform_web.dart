import 'dart:js_interop';

@JS('tongyeokContactNames')
external JSFunction? get _bridge;

@JS('addEventListener')
external void _addListener(JSString type, JSFunction callback);

@JS('removeEventListener')
external void _removeListener(JSString type, JSFunction callback);

bool get androidContactsAvailable => _bridge != null;

void Function() onAndroidContactsReady(void Function() callback) {
  final type = 'tongyeok-contact-names-ready'.toJS;
  final listener = ((JSAny? event) => callback()).toJS;
  _addListener(type, listener);
  return () => _removeListener(type, listener);
}

Future<void> _pending = Future.value();

Future<Object?> requestAndroidContacts(Map<String, Object?> request) {
  final result = _pending.then((_) async {
    final bridge = _bridge;
    if (bridge == null) return null;
    final response = bridge.callAsFunction(null, request.jsify()) as JSPromise;
    return (await response.toDart).dartify();
  });
  _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
  return result;
}
