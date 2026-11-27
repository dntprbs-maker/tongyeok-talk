import 'package:flutter/foundation.dart';

const socialLocalPreview =
    kDebugMode && bool.fromEnvironment('TONGYEOK_SOCIAL_LOCAL_PREVIEW');

const _androidPreviewHost = String.fromEnvironment('TONGYEOK_ANDROID_PREVIEW_HOST');
const _publishedHost = 'tongyeok-talk-lab-20261024.web.app';

String get mobileTongyeokHost =>
    kDebugMode &&
        defaultTargetPlatform == TargetPlatform.android &&
        RegExp(r'^tongyeok-talk-lab-20261024--android2009-[a-z0-9]+\.web\.app$')
            .hasMatch(_androidPreviewHost)
    ? _androidPreviewHost
    : _publishedHost;

bool isTongyeokMobilePage(Uri uri) =>
    uri.scheme == 'https' &&
    (uri.host == _publishedHost || uri.host == mobileTongyeokHost) &&
    !uri.hasPort &&
    uri.userInfo.isEmpty &&
    (uri.path == '/mobile' || uri.path.startsWith('/mobile/'));

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
  if (isTongyeokMobilePage(uri)) return true;
  const root = '/tongyeok-talk';
  return uri.scheme == 'https' &&
      uri.host.toLowerCase() == 'dntprbs-maker.github.io' &&
      !uri.hasPort &&
      uri.userInfo.isEmpty &&
      (uri.path == root || uri.path.startsWith('$root/'));
}
