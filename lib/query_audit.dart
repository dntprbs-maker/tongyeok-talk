import 'package:flutter/foundation.dart';

/// Local verification only; no message text, names, phones or credentials.
void auditQuery(String event, [Map<String, Object?> values = const {}]) {
  if (const bool.fromEnvironment('TONGYEOK_QUERY_AUDIT')) {
    debugPrint('TT_QUERY $event $values');
  }
}
