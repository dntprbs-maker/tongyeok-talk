import 'package:flutter_test/flutter_test.dart';
import 'package:bridgechat/app_build_number.dart';

void main() {
  test(
    'the web settings receive the installed build from the app entry URL',
    () {
      final entry = Uri.parse('https://example.com/mobile/?ref=abc#keep');
      final opened = withAppBuildNumber(entry, build: '2005');
      expect(opened.queryParameters['ref'], 'abc');
      expect(opened.fragment, 'keep');
      expect(appBuildNumber(opened), '2005');
      expect(appBuildNumber(entry), isNull);
      expect(
        appBuildNumber(entry.replace(query: 'appBuild=2004&appBuild=3004')),
        isNull,
      );
      expect(withAppBuildNumber(entry, build: '<unsafe>'), entry);
    },
  );
}
