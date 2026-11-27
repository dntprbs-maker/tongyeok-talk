import 'package:flutter/foundation.dart';

const socialLocalPreview =
    (kDebugMode && bool.fromEnvironment('TONGYEOK_SOCIAL_LOCAL_PREVIEW')) ||
    bool.fromEnvironment('TONGYEOK_IOS_UPDATE_QA');

/// The embedded app may navigate only within the deployed application path.
/// This check is shared by navigation and any future native bridge: allowing
/// JavaScript for a page does not grant arbitrary pages access to app features.
bool isTrustedTongyeokPage(Uri uri) {
  if (socialLocalPreview &&
      uri.scheme == 'http' &&
      uri.host == '127.0.0.1' &&
      uri.port == 8768 &&
      uri.userInfo.isEmpty) {
    return true;
  }
  if (uri.scheme == 'https' &&
      uri.host == 'tongyeok-talk-lab-20261024.web.app' &&
      !uri.hasPort &&
      uri.userInfo.isEmpty &&
      (uri.path == '/mobile' || uri.path.startsWith('/mobile/'))) {
    return true;
  }
  const root = '/tongyeok-talk';
  return uri.scheme == 'https' &&
      uri.host.toLowerCase() == 'dntprbs-maker.github.io' &&
      !uri.hasPort &&
      uri.userInfo.isEmpty &&
      (uri.path == root || uri.path.startsWith('$root/'));
}
