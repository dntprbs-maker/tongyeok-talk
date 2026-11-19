/// The embedded app may navigate only within the deployed application path.
/// This check is shared by navigation and any future native bridge: allowing
/// JavaScript for a page does not grant arbitrary pages access to app features.
bool isTrustedTongyeokPage(Uri uri) {
  const root = '/tongyeok-talk';
  return uri.scheme == 'https' &&
      uri.host.toLowerCase() == 'dntprbs-maker.github.io' &&
      !uri.hasPort &&
      uri.userInfo.isEmpty &&
      (uri.path == root || uri.path.startsWith('$root/'));
}
