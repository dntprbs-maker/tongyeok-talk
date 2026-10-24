# AI 번역 비교 설정 — 2026-10-25 기준

아빠가 지정한 세 모델만 비교한다. 2026-10-25 실제 비교 후 아빠 지시로 `selectedModel`을 `openai/gpt-6-luna`로 설정했다. 몽골어 사용자 품질 검수는 미완료다.

|모델|정확한 OpenRouter ID|입력/출력 100만 토큰당 USD (확인 시점 기본 요금)|
|---|---|---|
|Tencent Hy-MT2 30B-A3B|tencent/hy-mt2-30b-a3b|0.074 / 0.295|
|GPT-6 Luna|openai/gpt-6-luna|0.10 / 0.50|
|Claude Haiku 5.5|anthropic/claude-haiku-5.5|0.10 / 0.50|

공식 목록: https://openrouter.ai/api/v1/models . 긴 입력·제공업체·요금 변경 등으로 실제 청구액은 다를 수 있다. 결과의 costUsd가 없으면 비용을 추정해 실제 비용으로 보고하지 않는다.

## 실행

Node 22 이상, 저장소 루트에서 `node tools/compare_translations.mjs`는 네트워크·비용 없는 준비 확인이다.

실제 비교는 기존 통역톡 키를 저장소 밖의 파일로 안전하게 보관하고 `TONGYEOK_OPENROUTER_KEY_FILE`에 그 경로를 지정한 뒤 `node tools/compare_translations.mjs --live`로 실행한다. 또는 서버 프로세스의 `OPENROUTER_API_KEY` 환경변수를 사용한다. 키를 명령 인수, 소스, Flutter 설정, docs, 웹 빌드에 넣지 않는다.

시험 문장 6개 × 모델 3개 = 최대 18회 호출. 자동 모델 대체·자동 유료 재시도 없음. 인증·잔액 오류는 중단한다. 결과는 Git 제외 경로 `artifacts/translation-comparison/<실행시각>/` 아래 JSON과 몽골어 검수용 REVIEW.md로 저장한다. 날짜·원문·번역문·요청/응답 모델·시간·토큰·반환된 비용·오류·검수 의견을 구분한다. 원문은 합성 개발 문장만 사용한다.

## 완료 범위

PC 번역 worker를 실제 독립 Firebase 채팅에 연결했다. 세 모델 직접 비교18회, Luna 실제 채팅10회(9메시지 및 재시도1회)의 원문·응답을 기록했다. 채팅 UI 양언어 표시와 실패 후 재시도를 확인했다. 번역 성공을 언어 품질 통과로 간주하지 않는다. 공개 배포·키 신규 생성·요금 충전은 하지 않았다.

## PC 번역 worker 실행

서버에 `TONGYEOK_PROJECT=tongyeok-talk-lab-20261024`, `TONGYEOK_OPERATOR_AUTH_MODULE`(저장소 밖 승인된 operator 인증 모듈 URL), `TONGYEOK_OPENROUTER_KEY_FILE`(저장소 밖 기존 키 경로)을 지정하고 `node tools/translation_worker.mjs` 실행. 선택적으로 `TONGYEOK_TRANSLATION_HEALTH_FILE`에 비공개 상태 파일 경로를 지정한다. 단일 프로세스로만 실행한다. 다른 앱의 운영 프로젝트를 지정할 수 없도록 차단한다.

worker가 실행된 뒤 도착한 메시지만 자동 처리한다. 중단 중 도착한 원문과 이전 기록은 보존되지만 자동 소급 번역은 하지 않는다. 60초 이상 번역 대기 또는 실패 화면에서 참여자가 재시도할 수 있다. 메시지당 최대3회, 누적 최대200호출 또는 기록 비용0.25달러 한도로 제한한다. 비용 미반환 시 200호출 상한은 유지한다. 재시도도 실제 비용이 들 수 있다. PC·네트워크·인증이 필요하며 자동 시작/상시 운영 보장은 없다.

실제 채팅 감사 기록은 `artifacts/chat-translations/audit.jsonl`, 누적 제한은 같은 폴더 `budget.json`. Git 제외 대상이며 기록을 임의로 삭제하거나 예산을 초기화하지 않는다. 몽골어 사용자에게 공유하는 검수 자료에는 개발 합성 문장만 넣는다.

Google 검수 문서: https://docs.google.com/document/d/1LZNCWoBAhoSojxeMJYypfJsHz1AsGu_OY_qFyAanOq4
