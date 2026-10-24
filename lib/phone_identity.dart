class PhoneIdentity {
  final String e164;
  const PhoneIdentity._(this.e164);
  String get directoryKey => e164.substring(1);
  // Firebase's password credential transport. This is not the user's email.
  String get authAlias => 'p$directoryKey@phone.tongyeok.invalid';

  /// Korea-only service entry point; language never changes phone identity.
  /// The legacy parser remains available to preserve earlier test accounts.
  static PhoneIdentity parseKorean(String input) {
    final phone = parse(input);
    if (!phone.e164.startsWith('+82')) {
      throw const FormatException('phoneInvalid');
    }
    return phone;
  }

  static PhoneIdentity parse(String input, {String defaultCountry = '82'}) {
    var value = input.trim().replaceAll(RegExp(r'[\s().-]'), '');
    if (value.startsWith('00')) value = '+${value.substring(2)}';
    if (!RegExp(r'^\+?[0-9]+$').hasMatch(value)) {
      throw const FormatException('phoneInvalid');
    }
    String country, national;
    if (value.startsWith('+82')) {
      country = '82';
      national = value.substring(3);
    } else if (value.startsWith('+976')) {
      country = '976';
      national = value.substring(4);
    } else if (value.startsWith('+')) {
      throw const FormatException('phoneInvalid');
    } else {
      country = defaultCountry;
      national = value;
    }
    if (country == '82') {
      if (national.startsWith('0')) national = national.substring(1);
      if (!RegExp(
        r'^(?:10[0-9]{8}|1[16789][0-9]{7,8}|2[0-9]{7,8}|[3-6][1-5][0-9]{7,8}|70[0-9]{8})$',
      ).hasMatch(national)) {
        throw const FormatException('phoneInvalid');
      }
    } else if (country == '976') {
      if (!RegExp(r'^[1-9][0-9]{7}$').hasMatch(national)) {
        throw const FormatException('phoneInvalid');
      }
    } else {
      throw const FormatException('phoneInvalid');
    }
    return PhoneIdentity._('+$country$national');
  }
}
