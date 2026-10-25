import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridgechat/read_receipts.dart';
import 'package:bridgechat/app_language.dart';

void main() {
  testWidgets(
    'rebuilds reuse the count; revision/read cursor refresh; duplicate cursor does not',
    (t) async {
      final receipts = StreamController<Timestamp?>.broadcast();
      int calls = 0;
      Future<int> count(Timestamp? cursor) async {
        calls++;
        return cursor == null ? 120 : 0;
      }

      Widget page(int rev) => LanguageScope(
        child: MaterialApp(
          home: Scaffold(
            body: UnreadAvatar(
              conversationId: 'room',
              uid: 'me',
              group: false,
              messageRevision: Timestamp(rev, 0),
              receiptStream: receipts.stream,
              countLoader: count,
            ),
          ),
        ),
      );
      await t.pumpWidget(page(1));
      receipts.add(null);
      await t.pump();
      await t.pump(const Duration(milliseconds: 110));
      await t.pump();
      expect(calls, 1);
      expect(find.text('99+'), findsOneWidget);
      await t.pumpWidget(page(1));
      await t.pump(const Duration(milliseconds: 110));
      expect(calls, 1);
      await t.pumpWidget(page(2));
      await t.pump(const Duration(milliseconds: 110));
      await t.pump();
      expect(calls, 2);
      receipts.add(Timestamp(3, 0));
      await t.pump();
      await t.pump(const Duration(milliseconds: 110));
      await t.pump();
      expect(calls, 3);
      expect(t.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
      receipts.add(Timestamp(3, 0));
      await t.pump();
      await t.pump(const Duration(milliseconds: 110));
      expect(calls, 3);
      await t.pumpWidget(const SizedBox());
      await receipts.close();
    },
  );
  testWidgets('a slow older response cannot overwrite a newer unread count', (
    t,
  ) async {
    final receipts = StreamController<Timestamp?>.broadcast();
    final requests = <Completer<int>>[];
    Future<int> count(Timestamp? cursor) {
      final c = Completer<int>();
      requests.add(c);
      return c.future;
    }

    Widget page(int rev) => LanguageScope(
      child: MaterialApp(
        home: Scaffold(
          body: UnreadAvatar(
            conversationId: 'room',
            uid: 'me',
            group: true,
            messageRevision: Timestamp(rev, 0),
            receiptStream: receipts.stream,
            countLoader: count,
          ),
        ),
      ),
    );
    await t.pumpWidget(page(1));
    receipts.add(null);
    await t.pump();
    await t.pump(const Duration(milliseconds: 110));
    await t.pumpWidget(page(2));
    await t.pump(const Duration(milliseconds: 110));
    expect(requests.length, 2);
    requests[1].complete(2);
    await t.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
    requests[0].complete(99);
    await t.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
    expect(find.text('99'), findsNothing);
    await t.pumpWidget(const SizedBox());
    await receipts.close();
  });
  testWidgets(
    'failed aggregation shows a retry affordance instead of false zero',
    (t) async {
      final receipts = StreamController<Timestamp?>.broadcast();
      var calls = 0;
      await t.pumpWidget(
        LanguageScope(
          child: MaterialApp(
            home: Scaffold(
              body: UnreadAvatar(
                conversationId: 'room',
                uid: 'me',
                group: false,
                receiptStream: receipts.stream,
                countLoader: (_) async {
                  if (calls++ == 0) throw StateError('offline');
                  return 3;
                },
              ),
            ),
          ),
        ),
      );
      receipts.add(null);
      await t.pump();
      await t.pump(const Duration(milliseconds: 110));
      await t.pump();
      expect(find.byIcon(Icons.sync_problem), findsOneWidget);
      await t.tap(find.byIcon(Icons.sync_problem));
      await t.pump(const Duration(milliseconds: 110));
      await t.pump();
      expect(find.text('3'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await receipts.close();
    },
  );
}
