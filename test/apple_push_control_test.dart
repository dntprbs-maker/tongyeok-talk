import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridgechat/app_language.dart';
import 'package:bridgechat/settings_screen.dart';

void main() {
  testWidgets(
    'Apple offers enable only and cannot disable or claim unsupported is enabled',
    (t) async {
      var enabled = 0;
      for (final status in ['off', 'enabled', 'unsupported', 'denied']) {
        await t.pumpWidget(
          LanguageScope(
            child: MaterialApp(
              home: Scaffold(
                body: ApplePushEnableControl(
                  status: status,
                  busy: false,
                  onEnable: () => enabled++,
                ),
              ),
            ),
          ),
        );
        expect(find.byType(Switch), findsNothing);
        final button = t.widget<FilledButton>(find.byType(FilledButton));
        if (status == 'enabled' || status == 'unsupported') {
          expect(button.onPressed, isNull);
        } else {
          final before = enabled;
          await t.tap(find.byType(FilledButton));
          expect(enabled, before + 1);
        }
      }
    },
  );
}
