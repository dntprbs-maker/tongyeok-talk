import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'dart:convert';
import 'package:sembast/sembast_io.dart';
import 'package:bridgechat/local_archive.dart';
import 'package:bridgechat/guest_chat_screen.dart';

void main() {
  test(
    'guest JSON and old handset records preserve Korean and Mongolian',
    () async {
      const ko = '정문 앞에서 기다리고 있어요.', mn = 'Гол хаалганы өмнө хүлээж байна.';
      expect(
        decodeGuestResponse(utf8.encode(jsonEncode({'name': ko, 'text': mn}))),
        {'name': ko, 'text': mn},
      );
      final factory = databaseFactoryIo;
      final directory = await Directory('build').createTemp('guest-encoding-');
      final path = '${directory.path}/archive.db';
      final db = await factory.openDatabase(path);
      final rooms = stringMapStoreFactory.store('rooms'),
          messages = stringMapStoreFactory.store('messages');
      await rooms.record('owner/guest:one').put(db, {
        'uid': 'owner',
        'room': 'guest:one',
        'name': latin1.decode(utf8.encode('손님')),
        'guest': true,
        'time': 1,
      });
      await messages.record('owner/guest:one/message').put(db, {
        'uid': 'owner',
        'room': 'guest:one',
        'id': 'message',
        'time': 1,
        'original': latin1.decode(utf8.encode(ko)),
        'translation': latin1.decode(utf8.encode(mn)),
      });
      final archive = LocalArchive(() async => db);
      expect((await archive.rooms('owner').first).single['name'], '손님');
      final record =
          (await archive.messages('owner', 'guest:one').first).single;
      expect(record['original'], ko);
      expect(record['translation'], mn);
      await db.close();
      await factory.deleteDatabase(path);
      await directory.delete();
    },
  );
  test(
    'archive survives reopen; UID isolation, translation merge, no lost messages on empty sync',
    () async {
      final factory = databaseFactoryIo;
      final directory = await Directory('build').createTemp('guest-archive-');
      final path = '${directory.path}/archive.db';
      var db = await factory.openDatabase(path);
      final archive = LocalArchive(() async => db);
      final rows = [
        <String, dynamic>{
          'id': '1',
          'original': '안녕',
          'translation': 'Сайн уу',
          'source': 'ko',
          'mine': false,
          'time': 1,
          'status': 'done',
        },
      ];
      await archive.save('owner', 'room', '손님', true, rows);
      await archive.save('other', 'room', '다른 사람', false, [
        {...rows.first, 'original': '다른 내용'},
      ]);
      await archive.save('owner', 'room', '손님', true, []);
      await archive.save('owner', 'room', '손님', true, [
        {...rows.first, 'translation': ''},
      ]);
      expect(
        (await archive.messages('owner', 'room').first).single['translation'],
        'Сайн уу',
      );
      await db.close();
      db = await factory.openDatabase(path);
      final reopened = LocalArchive(() async => db);
      expect(
        (await reopened.messages('owner', 'room').first).single['original'],
        '안녕',
      );
      expect(
        (await reopened.messages('other', 'room').first).single['original'],
        '다른 내용',
      );
      expect(await reopened.rooms('unknown').first, isEmpty);
      await reopened.removeAccount('owner');
      expect(await reopened.rooms('owner').first, isEmpty);
      expect((await reopened.rooms('other').first).length, 1);
      await db.close();
      await factory.deleteDatabase(path);
      await directory.delete();
    },
  );
}
