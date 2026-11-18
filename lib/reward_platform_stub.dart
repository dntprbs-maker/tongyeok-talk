bool get supported => false;
bool get testMode => true;
void Function() listenAvailability(void Function() callback) => () {};
Future<void> prepare(String uid) async => throw StateError('adUnavailable');
Future<bool> show(
  String uid,
  String sessionId,
  String adUnitId,
  bool testAds,
) async => throw StateError('adUnavailable');
Future<void> privacy(String uid) async => throw StateError('adUnavailable');
