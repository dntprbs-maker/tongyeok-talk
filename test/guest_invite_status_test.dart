import 'package:bridgechat/guest_chat_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'QR issuance, empty names, and closed rooms do not count as guest joins',
    () {
      final expiry = DateTime.utc(2026, 11, 27);
      final waiting = {
        'status': 'waiting',
        'guestName': '',
        'expiresAt': Timestamp.fromDate(expiry),
      };
      final joined = {...waiting, 'status': 'active', 'guestName': '검수 손님'};
      expect(joinedGuestRoomExpiry(waiting), isNull);
      expect(joinedGuestRoomExpiry({...joined, 'guestName': ' '}), isNull);
      expect(joinedGuestRoomExpiry({...joined, 'status': 'ended'}), isNull);
      expect(joinedGuestRoomExpiry({...joined, 'expiresAt': null}), isNull);
      expect(joinedGuestRoomExpiry(joined)?.toUtc(), expiry);
    },
  );
}
