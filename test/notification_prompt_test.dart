import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridgechat/notification_prompt.dart';
import 'package:bridgechat/notice_bell.dart';
import 'package:bridgechat/recent_conversations_screen.dart';
import 'package:bridgechat/app_language.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.instance.initialize();
  });
  Widget page(Widget child) => LanguageScope(
    child: MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  testWidgets(
    'the bell keeps its shape and uses the dot only for unread alerts',
    (t) async {
      var opened = 0;
      for (final unread in [false, true]) {
        await t.pumpWidget(
          page(NoticeBell(hasUnread: unread, onOpen: () => opened++)),
        );
        await t.pumpAndSettle();
        expect(t.widget<Badge>(find.byType(Badge)).isLabelVisible, unread);
        expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
        await t.tap(find.byType(IconButton));
      }
      expect(opened, 2);
    },
  );
  testWidgets('incoming notices offers direct enable while the device is off', (
    t,
  ) async {
    await t.pumpWidget(
      page(
        NotificationPrompt(
          canDismiss: false,
          readState: () async => 'off',
          enable: () async => 'enabled',
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('이 기기의 알림이 꺼져 있어요'), findsOneWidget);
    expect(find.text('나중에'), findsNothing);
    await t.tap(find.text('알림 켜기'));
    await t.pumpAndSettle();
    expect(find.text('이 기기의 알림이 꺼져 있어요'), findsNothing);
  });
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
