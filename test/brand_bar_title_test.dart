import 'package:bridgechat/app_language.dart';
import 'package:bridgechat/brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('the complete Mongolian name fits a narrow toolbar title', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'tongyeok.language': 'mn'});
    await AppLanguage.instance.initialize();
    addTearDown(() async {
      SharedPreferences.setMockInitialValues({});
      await AppLanguage.instance.initialize();
    });
    await tester.pumpWidget(
      LanguageScope(
        child: const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 124, child: BrandBarTitle()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final title = find.text('Орчуулагч Ток');
    expect(title, findsOneWidget);
    expect(tester.widget<Text>(title).overflow, isNot(TextOverflow.ellipsis));
    expect(tester.getRect(title).right, lessThanOrEqualTo(124.1));
    expect(tester.takeException(), isNull);
  });
}
