import 'package:bridgechat/app_language.dart';
import 'package:bridgechat/new_conversation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'phone label and helper stay outside the field at large text size',
    (tester) async {
      tester.view.physicalSize = const Size(320, 680);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(1.5)),
                child: child!,
              ),
          home: const NewConversationScreen(),
        ),
      );
      await tester.pumpAndSettle();
      final language = AppLanguage.instance;
      final invite = tester.getRect(find.text(language.text('guestInvite')));
      final title = tester.getRect(find.text(language.text('searchPhone')));
      final field = tester.getRect(find.byKey(const ValueKey('search-phone')));
      final help = tester.getRect(find.text(language.text('phoneSearchHelp')));
      expect(title.top, greaterThan(invite.bottom));
      expect(field.top, greaterThanOrEqualTo(title.bottom + 8));
      expect(field.height, greaterThanOrEqualTo(58));
      expect(help.top, greaterThanOrEqualTo(field.bottom + 8));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('contact search focuses after the mobile prefix', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NewConversationScreen()));
    await tester.pumpAndSettle();
    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.focusNode.hasFocus, isTrue);
    expect(field.controller.text, '010-');
    expect(field.controller.selection.baseOffset, 4);

    for (final input in [
      '010-12345678',
      '010-010-1234-5678',
      '010-1234-5678',
    ]) {
      await tester.enterText(find.byType(TextField), input);
      expect(field.controller.text, '010-1234-5678');
      expect(field.controller.selection.baseOffset, 13);
    }

    await tester.enterText(find.byType(TextField), '');
    expect(field.controller.text, '010-');
    expect(field.controller.selection.baseOffset, 4);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
