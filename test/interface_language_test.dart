import 'package:bridgechat/app_language.dart';
import 'package:bridgechat/reward_ads_section.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'display choice leaves the Mongolian account and credits policy intact',
    () async {
      SharedPreferences.setMockInitialValues({'tongyeok.language': 'ko'});
      final language = AppLanguage();
      await language.initialize();
      language.useAccountLanguage('mado', 'mn');
      expect(language.displayCode, 'mn');
      await language.selectDisplayLanguage('mado', 'ko');
      expect(language.text('interfaceLanguage'), '화면 언어');
      expect(language.code, 'mn');
      expect(language.profileLanguage, 'Mongolian');
      expect(
        isRewardLeader({'preferredLanguage': language.profileLanguage}),
        isFalse,
      );

      language.keepAccountLanguageFor('another-account');
      expect(language.code, 'ko');
      await language.selectDisplayLanguage('mado', 'mn');
      expect(language.displayCode, 'ko');

      final reopened = AppLanguage();
      await reopened.initialize();
      reopened.useAccountLanguage('mado', 'mn');
      expect(reopened.displayCode, 'ko');
      await reopened.selectDisplayLanguage('mado', 'mn');
      expect(reopened.text('interfaceLanguage'), 'Дэлгэцийн хэл');
      expect(reopened.profileLanguage, 'Mongolian');
    },
  );
}
