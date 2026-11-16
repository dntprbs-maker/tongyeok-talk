import 'package:bridgechat/new_conversation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('contact search focuses after the mobile prefix', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: NewConversationScreen()),
    );
    await tester.pumpAndSettle();
    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.focusNode.hasFocus, isTrue);
    expect(field.controller.text, '010-');
    expect(field.controller.selection.baseOffset, 4);

    for (final input in ['010-12345678', '010-010-1234-5678', '010-1234-5678']) {
      await tester.enterText(find.byType(TextField), input);
      expect(field.controller.text, '010-1234-5678');
      expect(field.controller.selection.baseOffset, 13);
    }

    await tester.enterText(find.byType(TextField), '');
    expect(field.controller.text, '010-');
    expect(field.controller.selection.baseOffset, 4);
  });
}
