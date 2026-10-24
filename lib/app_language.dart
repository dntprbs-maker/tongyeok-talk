import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Exactly two UI languages. User messages and names are never translated here.
class AppLanguage extends ChangeNotifier {
  static final instance = AppLanguage();
  String _code = 'ko';
  String get code => _code;
  String get profileLanguage => _code == 'mn' ? 'Mongolian' : 'Korean';
  Future<void> initialize() async {
    final saved = (await SharedPreferences.getInstance()).getString(
      'tongyeok.language',
    );
    _code = saved == 'mn' ? 'mn' : 'ko';
  }

  Future<void> select(String code) async {
    if (!['ko', 'mn'].contains(code)) return;
    _code = code;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(
      'tongyeok.language',
      code,
    );
  }

  String text(String key, [Map<String, String> values = const {}]) {
    final pair = messages[key];
    assert(pair != null, 'Missing translation: $key');
    var text = pair?[_code == 'mn' ? 1 : 0] ?? key;
    for (final item in values.entries) {
      text = text.replaceAll('{${item.key}}', item.value);
    }
    return text;
  }
}

class LanguageScope extends InheritedNotifier<AppLanguage> {
  LanguageScope({super.key, required super.child})
    : super(notifier: AppLanguage.instance);
  static AppLanguage of(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<LanguageScope>();
    return AppLanguage.instance;
  }
}

String tr(
  BuildContext context,
  String key, [
  Map<String, String> values = const {},
]) => LanguageScope.of(context).text(key, values);

class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key});
  @override
  Widget build(BuildContext context) {
    final lang = LanguageScope.of(context);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      children: [
        for (final entry in const {'ko': '한국어', 'mn': 'Монгол'}.entries)
          ChoiceChip(
            label: Text(entry.value),
            selected: lang.code == entry.key,
            onSelected: (_) => lang.select(entry.key),
          ),
      ],
    );
  }
}

const Map<String, List<String>> messages = {
  'app': ['통역톡', 'Орчуулагч Ток'],
  'language': ['사용 언어', 'Хэл сонгох'],
  'preview': [
    '원문 채팅 시험판 · 자동번역은 준비 중입니다.',
    'Эх бичвэрийн чатын туршилт · Автомат орчуулга бэлтгэгдэж байна.',
  ],
  'welcome': ['이야기를 이어주는 통역톡', 'Харилцааг холбох Орчуулагч Ток'],
  'intro': [
    '이름과 전화번호로 시작하세요.\n한국어와 몽골어로 함께 이야기해요.',
    'Нэр, утасны дугаараараа эхлээрэй.\nСолонгос, монгол хэлээр хамтдаа ярилцъя.',
  ],
  'signIn': ['로그인', 'Нэвтрэх'],
  'signUp': ['회원가입', 'Бүртгүүлэх'],
  'signInTitle': ['통역톡 로그인', 'Орчуулагч Ток — Нэвтрэх'],
  'signUpTitle': ['통역톡 회원가입', 'Орчуулагч Ток — Бүртгүүлэх'],
  'name': ['이름', 'Нэр'],
  'nameHint': ['대화 상대에게 보여줄 이름', 'Харилцагчид харагдах нэр'],
  'phone': ['전화번호', 'Утасны дугаар'],
  'country': ['국가번호', 'Улсын код'],
  'korea': ['대한민국', 'БНСУ'],
  'mongolia': ['몽골', 'Монгол'],
  'phoneHint': ['예: 010-1234-5678', 'Жишээ: 9911-2233'],
  'password': ['비밀번호', 'Нууц үг'],
  'showPassword': ['비밀번호 보기', 'Нууц үг харах'],
  'hidePassword': ['비밀번호 숨기기', 'Нууц үг нуух'],
  'nameRequired': ['이름을 1~40자로 입력해 주세요.', 'Нэрээ 1–40 тэмдэгтээр оруулна уу.'],
  'phoneInvalid': [
    '전화번호와 국가번호를 확인해 주세요.',
    'Утасны дугаар болон улсын кодоо шалгана уу.',
  ],
  'passwordShort': [
    '비밀번호를 8자 이상 입력해 주세요.',
    'Нууц үгээ 8-аас доошгүй тэмдэгтээр оруулна уу.',
  ],
  'passwordRequired': ['비밀번호를 입력해 주세요.', 'Нууц үгээ оруулна уу.'],
  'phoneNotice': [
    '전화번호를 로그인과 상대 찾기에 사용해요. 현재 문자 본인확인은 제공하지 않아요.',
    'Утасны дугаарыг нэвтрэх болон харилцагч хайхад ашиглана. Одоогоор SMS баталгаажуулалтгүй.',
  ],
  'phoneInUse': [
    '이미 가입된 전화번호예요. 로그인해 주세요.',
    'Энэ дугаар бүртгэлтэй байна. Нэвтэрнэ үү.',
  ],
  'invalidLogin': [
    '전화번호 또는 비밀번호가 맞지 않아요.',
    'Утасны дугаар эсвэл нууц үг буруу байна.',
  ],
  'tooManyAttempts': ['잠시 후 다시 시도해 주세요.', 'Түр хүлээгээд дахин оролдоно уу.'],
  'networkError': [
    '연결을 확인하고 다시 시도해 주세요.',
    'Холболтоо шалгаад дахин оролдоно уу.',
  ],
  'permissionError': [
    '접근할 수 없어요. 다시 로그인해 주세요.',
    'Хандах эрхгүй байна. Дахин нэвтэрнэ үү.',
  ],
  'genericError': [
    '처리하지 못했어요. 잠시 후 다시 시도해 주세요.',
    'Үйлдэл амжилтгүй. Түр хүлээгээд дахин оролдоно уу.',
  ],
  'alreadyAccount': ['이미 가입했나요? 로그인', 'Бүртгэлтэй юу? Нэвтрэх'],
  'newAccount': ['처음인가요? 회원가입', 'Шинээр бүртгүүлэх'],
  'chats': ['대화', 'Чат'],
  'newChat': ['새 대화', 'Шинэ чат'],
  'settings': ['설정', 'Тохиргоо'],
  'signOut': ['로그아웃', 'Гарах'],
  'noChats': [
    '아직 대화가 없어요.\n새 대화에서 상대 전화번호를 찾아보세요.',
    'Одоогоор чат алга.\nШинэ чат нээгээд харилцагчийн дугаарыг хайна уу.',
  ],
  'noMessages': ['첫 메시지를 보내보세요.', 'Эхний зурвасаа илгээгээрэй.'],
  'message': ['메시지', 'Зурвас'],
  'send': ['보내기', 'Илгээх'],
  'messageTooLong': [
    '메시지는 2,000자까지 보낼 수 있어요.',
    'Зурвас 2,000 хүртэл тэмдэгттэй байна.',
  ],
  'searchPhone': ['상대 전화번호', 'Харилцагчийн утасны дугаар'],
  'findPhoneHint': [
    '상대의 정확한 전화번호를 입력해 주세요.',
    'Харилцагчийн утасны дугаарыг бүтнээр оруулна уу.',
  ],
  'startChat': ['대화 시작', 'Чат эхлүүлэх'],
  'addParticipant': ['참여자 추가', 'Оролцогч нэмэх'],
  'groupChat': ['단체 대화', 'Бүлгийн чат'],
  'createGroup': ['단체방 만들기', 'Бүлэг үүсгэх'],
  'userNotFound': [
    '가입된 상대를 찾지 못했어요. 전화번호를 확인해 주세요.',
    'Бүртгэлтэй хэрэглэгч олдсонгүй. Утасны дугаарыг шалгана уу.',
  ],
  'selfChat': [
    '다른 사람의 전화번호를 입력해 주세요.',
    'Өөр хүний утасны дугаарыг оруулна уу.',
  ],
  'alreadyAdded': ['이미 추가한 사람이에요.', 'Энэ оролцогчийг нэмсэн байна.'],
  'maxParticipants': [
    '상대는 10명까지 추가할 수 있어요.',
    '10 хүртэл харилцагч нэмэх боломжтой.',
  ],
  'removeParticipant': ['선택에서 빼기', 'Сонголтоос хасах'],
  'participants': ['참여자', 'Оролцогчид'],
  'groupSettings': ['단체방 설정', 'Бүлгийн тохиргоо'],
  'groupName': ['단체방 이름', 'Бүлгийн нэр'],
  'save': ['저장', 'Хадгалах'],
  'saved': ['저장했어요.', 'Хадгаллаа.'],
  'groupNameInvalid': [
    '단체방 이름을 1~100자로 입력해 주세요.',
    'Бүлгийн нэрийг 1–100 тэмдэгтээр оруулна уу.',
  ],
  'unknownUser': ['사용자', 'Хэрэглэгч'],
  'groupDefault': ['단체 대화', 'Бүлгийн чат'],
  'original': ['원문 보기', 'Эх бичвэр харах'],
  'translated': ['번역문 보기', 'Орчуулга харах'],
  'translationInfo': ['{from} → {to} 번역', '{from} → {to} орчуулга'],
  'ko': ['한국어', 'Солонгос'],
  'mn': ['몽골어', 'Монгол'],
  'retry': ['다시 시도', 'Дахин оролдох'],
  'back': ['뒤로', 'Буцах'],
  'account': ['내 정보', 'Миний мэдээлэл'],
  'phoneUnverified': [
    '전화번호 등록 · 문자 본인확인 미적용',
    'Утасны дугаар бүртгэлтэй · SMS-ээр баталгаажаагүй',
  ],
  'legacyAccount': [
    '이전 시험 계정 · 기존 대화는 보관됩니다.',
    'Өмнөх туршилтын бүртгэл · Хуучин чат хадгалагдана.',
  ],
  'profileMissing': [
    '가입 정보를 마무리하려면 같은 전화번호와 비밀번호로 다시 가입해 주세요.',
    'Бүртгэлээ гүйцээхийн тулд ижил дугаар, нууц үгээр дахин бүртгүүлнэ үү.',
  ],
};
