# 통역톡 · Tongyeok Talk

BridgeChat를 재사용한 한국어·몽골어 자동번역 메신저 개발 프로젝트입니다.

## 현재 공개 시험판

**현재는 원문 채팅 시험판입니다. 자동번역·사진·푸시 알림은 아직 제공하지 않습니다.**

- 이메일로 가입하고 닉네임으로 상대를 찾습니다.
- 두 사람이 대화하거나 여러 사람을 선택해 단체방을 만들 수 있습니다.
- 메시지와 대화방은 별도의 무료 Firebase 시험 프로젝트에 보관됩니다.
- 공개 닉네임 검색 목록에는 이메일을 저장하지 않습니다. 대화는 방 참여자만 읽을 수 있도록 제한합니다.
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

## 라이선스

기반 원본: [av1155/bridgechat](https://github.com/av1155/bridgechat)

MIT License · Copyright (c) 2025 Andrea A. Venti Fuentes. [원본 라이선스](LICENSE.md)와 [변경 고지](NOTICE.md)를 보존합니다.
