import 'package:bridgechat/app_language.dart';
import 'package:bridgechat/contact_aliases.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only direct conversations identify a peer', () {
    final direct = {
      'participants': ['me', 'peer'],
    };
    expect(directChatPeer(direct, 'me'), 'peer');
    expect(directChatPeer({...direct, 'isGroup': true}, 'me'), isNull);
    expect(directChatPeer(direct, 'outsider'), isNull);
    expect(
      directChatPeer({
        'participants': ['me', 'me'],
      }, 'me'),
      isNull,
    );
  });

  testWidgets(
    'set, change, and clear a private alias while showing original name',
    (tester) async {
      String? saved;
      await tester.pumpWidget(
        LanguageScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder:
                    (context) => TextButton(
                      onPressed:
                          () => showDialog<void>(
                            context: context,
                            builder:
                                (_) => ContactAliasDialog(
                                  original: '홍길동',
                                  alias: saved,
                                  onSave: (value) async => saved = value,
                                ),
                          ),
                      child: const Text('열기'),
                    ),
              ),
            ),
          ),
        ),
      );

      Future<void> open() async {
        await tester.tap(find.text('열기'));
        await tester.pumpAndSettle();
        expect(find.textContaining('홍길동'), findsOneWidget);
        expect(find.text('별칭은 내 화면에만 보입니다.'), findsOneWidget);
      }

      await open();
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(find.text('별칭을 1~60자로 입력해 주세요.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '  현장 팀장님  ');
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(saved, '현장 팀장님');
      await open();
      await tester.enterText(find.byType(TextField), '현장 담당자');
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(saved, '현장 담당자');
      await open();
      await tester.tap(find.text('별칭 지우기'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
    },
  );
}
