import 'package:flutter_test/flutter_test.dart';
import 'package:bridgechat/mobile_web_navigation.dart';

void main() {
  test('only the exact HTTPS app origin and path are trusted', () {
    expect(isTrustedTongyeokPage(Uri.parse('https://dntprbs-maker.github.io/tongyeok-talk/')), isTrue);
    expect(isTrustedTongyeokPage(Uri.parse('https://dntprbs-maker.github.io/tongyeok-talk/chat')), isTrue);
    for (final value in [
      'http://dntprbs-maker.github.io/tongyeok-talk/',
      'https://dntprbs-maker.github.io.evil.example/tongyeok-talk/',
      'https://dntprbs-maker.github.io/tongyeok-talk-evil/',
      'https://dntprbs-maker.github.io:444/tongyeok-talk/',
      'https://dntprbs-maker.github.io/tongyeok-talk/../other',
      'https://dntprbs-maker.github.io/tongyeok-talk/%2e%2e/other',
      'https://dntprbs-maker.github.io/tongyeok-talk%2f..%2fother',
    ]) {
      expect(isTrustedTongyeokPage(Uri.parse(value)), isFalse, reason: value);
    }
  });
}
