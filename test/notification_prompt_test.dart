import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridgechat/notification_prompt.dart';
import 'package:bridgechat/recent_conversations_screen.dart';
import 'package:bridgechat/app_language.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    NotificationPromptState.launchWarningShown = false;
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.instance.initialize();
  });
  Widget page(Widget child) => LanguageScope(
    child: MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  testWidgets(
    'header bell opens settings without changing permission or showing a banner',
    (t) async {
      var opened = 0;
      var enabled = 0;
      for (final status in ['off', 'enabled', 'unsupported']) {
        await t.pumpWidget(
          page(
            NotificationPrompt(
              key: ValueKey(status),
              iconOnly: true,
              readState: () async => status,
              enable: () async {
                enabled++;
                return 'enabled';
              },
              onOpenSettings: () => opened++,
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('새 메시지를 놓치지 마세요'), findsNothing);
        expect(
          t.widget<Badge>(find.byType(Badge)).isLabelVisible,
          status != 'enabled',
        );
        await t.tap(find.byType(IconButton));
        expect(enabled, 0);
      }
      expect(opened, 3);
    },
  );
  testWidgets('already enabled device never shows the prompt', (t) async {
    await t.pumpWidget(
      page(NotificationPrompt(readState: () async => 'enabled')),
    );
    await t.pumpAndSettle();
    expect(find.text('알림 켜기'), findsNothing);
    expect(find.text('새 메시지를 놓치지 마세요'), findsNothing);
  });
  testWidgets(
    'disabled device shows prompt then hides immediately after enable',
    (t) async {
      var calls = 0;
      await t.pumpWidget(
        page(
          NotificationPrompt(
            readState: () async => 'off',
            enable: () async {
              calls++;
              return 'enabled';
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('알림 켜기'), findsOneWidget);
      await t.tap(find.text('알림 켜기'));
      await t.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('알림 켜기'), findsNothing);
      expect(find.text('알림 수신이 켜져 있어요.'), findsOneWidget);
    },
  );
  testWidgets('later dismisses the card without enabling notifications', (
    t,
  ) async {
    await t.pumpWidget(page(NotificationPrompt(readState: () async => 'off')));
    await t.pumpAndSettle();
    await t.tap(find.text('나중에'));
    await t.pumpAndSettle();
    expect(find.text('알림 켜기'), findsNothing);
  });
  testWidgets(
    'narrow mobile heading and Mongolian prompt fit without overflow',
    (t) async {
      t.view.physicalSize = const Size(320, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await AppLanguage.instance.select('mn');
      await t.pumpWidget(
        page(
          Column(
            children: [
              ConversationHomeHeading(
                displayName: 'Урт нэртэй туршилтын хэрэглэгч',
                onNewChat: () {},
              ),
              NotificationPrompt(readState: () async => 'off'),
            ],
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Мэдэгдэл асаах'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
