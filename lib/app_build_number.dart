const _nativeBuild = String.fromEnvironment('TONGYEOK_BUILD_NUMBER');
const _parameter = 'appBuild';
final _numericBuild = RegExp(r'^[0-9]{1,18}$');

Uri withAppBuildNumber(Uri entry, {String build = _nativeBuild}) {
  if (!_numericBuild.hasMatch(build)) return entry;
  return entry.replace(
    queryParameters: {...entry.queryParametersAll, _parameter: build},
  );
}

String? appBuildNumber(Uri location) {
  final candidates =
      location.queryParametersAll[_parameter] ?? const <String>[];
  final build = candidates.isEmpty ? _nativeBuild : candidates.singleOrNull;
  return build != null && _numericBuild.hasMatch(build) ? build : null;
}
