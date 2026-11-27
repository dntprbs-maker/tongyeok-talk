import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridgechat/app_update_screen.dart';

void main() {
  const channel = MethodChannel('tongyeok/app_update');
  TestWidgetsFlutterBinding.ensureInitialized();
  final messaging =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messaging.setMockMethodCallHandler(channel, null));

  test('store versions compare component by component', () {
    expect(compareAppVersions('1.0.10', '1.0.9'), greaterThan(0));
    expect(compareAppVersions('1.0', '1.0.0'), 0);
    expect(compareAppVersions('1.0.1', '1.0.3'), lessThan(0));
  });

  testWidgets('installed build and latest state disable the button', (
    tester,
  ) async {
    messaging.setMockMethodCallHandler(channel, (_) async => null);
    await tester.pumpWidget(
      const MaterialApp(
        home: AppUpdateScreen(
          android: true,
          mongolian: false,
          installed: ['1.0.3', '2005'],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1.0.3 · 빌드 2005'), findsOneWidget);
    expect(find.text('최신 버전입니다'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('failed lookup can retry and enable a published update', (
    tester,
  ) async {
    var attempts = 0;
    messaging.setMockMethodCallHandler(channel, (_) async {
      if (++attempts == 1) throw PlatformException(code: 'unavailable');
      return '2006';
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: AppUpdateScreen(
          android: true,
          mongolian: false,
          installed: ['1.0.3', '2005'],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('새 버전을 확인하지 못했어요'), findsOneWidget);
    await tester.tap(find.text('다시 확인'));
    await tester.pumpAndSettle();
    expect(find.text('새 빌드 2006'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });
}
