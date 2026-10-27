import 'package:flutter/foundation.dart';

Future<String> enablePush(String uid) async => 'unsupported';
Future<String> disablePush(String uid) async => 'unsupported';
Future<String> pushState(String uid) async => 'unsupported';

bool get appleMobile => defaultTargetPlatform == TargetPlatform.iOS;
