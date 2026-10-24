# 통역톡 · Interpreter Talk

BridgeChat를 재사용한 한국어·몽골어 자동번역 메신저 개발 프로젝트입니다.

## 현재 공개 시험판

**현재는 원문 채팅 시험판입니다. 자동번역·사진·푸시 알림은 아직 제공하지 않습니다.**

- 이름·전화번호·비밀번호로 가입하고, 전화번호·비밀번호로 로그인합니다.
- 한국(+82)·몽골(+976) 국가번호를 지원하고, 하이픈·공백·국가번호 표기를 통일합니다.
- 로그인 전부터 한국어·몽골어를 선택할 수 있습니다. 한국어가 기본이며 선택한 언어를 이 기기에 기억합니다.
- 가입·대화·설정·오류 안내는 선택한 언어로 표시합니다.
- 두 사람이 대화하거나 여러 사람을 선택해 단체방을 만들 수 있습니다.
- 메시지와 대화방은 별도의 무료 Firebase 시험 프로젝트에 보관됩니다.
- 상대를 찾으려면 정확한 전화번호가 필요합니다. 전화번호·사용자 전체 목록 조회와 다른 사람의 비공개 연락처 조회는 차단합니다. 대화는 방 참여자만 읽을 수 있습니다.
- 현재는 문자 본인인증을 제공하지 않으며 번호 소유가 인증됐다고 표시하지 않습니다. Firebase의 비밀번호 인증에 사용하는 내부 계정 표기는 사용자 이메일이 아닙니다. 비밀번호는 Firebase Auth가 관리합니다.
- 기존 이메일 시험 계정과 대화는 삭제하지 않으며, 새 가입·로그인 화면은 전화번호 방식을 사용합니다.
- 이 시험판에는 중요한 업무 정보나 개인정보를 입력하지 마세요. 무료 제공량이 소진되면 이용이 제한될 수 있습니다.

시험 주소: https://dntprbs-maker.github.io/tongyeok-talk/

화면은 GitHub Pages, 가입·대화 저장은 별도 Firebase Spark(결제 미연결) 프로젝트를 사용합니다. 기존 회사 운영 서비스와 데이터를 공유하지 않습니다. 코드 저장소가 공개되어도 비밀번호와 대화 내용은 포함하지 않습니다.

## 개발

Flutter stable SDK가 필요합니다.

```sh
flutter pub get
flutter run -d chrome
flutter build web --base-href /tongyeok-talk/ --output docs
python tools/version_web_assets.py
```

이번 저장소에는 먼저 만든 별도 로컬 수정본, 디버깅폰 계정, 대화 내보내기 파일, 운영자 인증정보를 포함하지 않습니다.

브랜드 원본: `assets/images/interpreter-talk.png`. 메인·가입 화면과 웹 앱 아이콘에 같은 이미지를 사용합니다. 아이콘 내보내기는 `tools/export_brand_assets.py`를 실행합니다.

화면·번호 검증: `flutter test`. 보안 규칙 시험: `npm ci` 후 Firestore 에뮬레이터가 127.0.0.1:8088에서 실행 중일 때 `npm run test:rules`. 자동시험과 실제 기기 수동 검증은 구분합니다.

## 라이선스

기반 원본: [av1155/bridgechat](https://github.com/av1155/bridgechat)

MIT License · Copyright (c) 2025 Andrea A. Venti Fuentes. [원본 라이선스](LICENSE.md)와 [변경 고지](NOTICE.md)를 보존합니다.
