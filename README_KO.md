# LanRead - iOS용 AI EPUB 리더

[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20iPadOS-lightgrey.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

LanRead는 SwiftUI 기반의 EPUB 리딩 앱으로, AI 기반 이해 보조와 로컬 우선 데이터 저장 방식을 중심으로 설계되었습니다.

## README 언어

- English: [README.md](README.md)
- 中文: [README_CN.md](README_CN.md)
- 日本語: [README_JA.md](README_JA.md)
- 한국어: [README_KO.md](README_KO.md)
- Español: [README_ES.md](README_ES.md)
- Deutsch: [README_DE.md](README_DE.md)
- Français: [README_FR.md](README_FR.md)

## 현재 상태 (코드 기준)

- 대상 플랫폼: iOS/iPadOS 16.0+
- Xcode 프로젝트 Marketing Version: `1.0.5`
- 가져오기 지원 포맷: Files 앱을 통한 `EPUB`
- 앱 UI 현지화: 영어, 중국어(간체), 일본어, 한국어
- 스크립트 기본 시뮬레이터(인자 생략 시): `iPhone 15 Pro`

## 최근 진행 상황 (2026-03 스냅샷)

- 리더 안정성 개선: 텍스트 선택 처리, 페이지 가장자리 상호작용, 가로 드리프트 방지 로직 보강.
- 하이라이트 흐름 강화: 다중 선택 병합, 노트 편집 동작 개선, 대형 공유 카드 이미지 내보내기 폴백 추가.
- AI 상호작용 개선: Ask AI 입력창 다중 줄 자동 크기 조절, 번역/설명/질문 동작 순서와 UX 정렬.
- 메트릭 정교화: 로컬 타임존 기준 7일/주/월 윈도우 정렬, summary/skimming 리더·AI 이벤트 카운터 분리.
- 스키밍 흐름 개선: 챕터 전환 안정화 후 인터스티셜 노출, 준비 상태 안내 메시지 명확화.

## 검증 스냅샷 (2026-03-31)

- `Isla ReaderTests`: 테스트 파일 17개, `@Test` 케이스 59개.
- `Isla ReaderUITests`: UI 스모크 테스트 파일 2개.
- `server/tests`: 백엔드 pytest 파일 5개.

## 구현된 기능

### 읽기/라이브러리
- EPUB 가져오기 (SHA-256 체크섬 기반 중복 감지)
- 라이브러리 검색, 즐겨찾기, 읽기 상태 필터
- 책 상세 패널(메타데이터, 파일 정보, 진행률)
- 하이라이트 다중 선택 병합 및 이미지 카드 공유
- 리더 기능:
  - 목차
  - 탭/스와이프 페이지 넘김
  - 챕터별 페이지 상태 유지
  - 테마/타이포그래피 설정
  - 북마크 추가/삭제 및 목록
  - 하이라이트와 노트
  - 하이라이트 원문 위치로 점프

### AI 기능
- 시작 읽기 AI 요약 (Core Data 캐시)
- 스트리밍 스타일 요약 표시
- 선택 텍스트/하이라이트 대상 AI 동작:
  - 번역
  - 설명
  - 질문
- AI 결과를 노트에 삽입
- 스키밍 모드:
  - 챕터 단위 AI 요약
  - 구조 포인트, 핵심 문장, 키워드, 점검 질문
  - 스키밍에서 본문 해당 위치로 바로 이동

### 진행률/알림/Live Activity
- 읽기 진행률 대시보드(주/월/년)
- 읽기 시간 및 목표 달성률 통계
- 일일 읽기 리마인더 알림
- 당일 읽기 진행 Live Activity 업데이트 (iOS 16.1+)

### 동기화/데이터 관리
- Notion OAuth 연결 플로우
- Notion 라이브러리 초기화(상위 페이지 선택, DB 생성)
- 하이라이트/노트 변경 큐 동기화(재시도/백오프)
- 읽기 데이터 내보내기/가져오기(JSON, 책 파일 제외)
- 캐시 사용량 조회 및 캐시 정리
- 로컬 데이터 전체 초기화(Core Data + EPUB 파일 + 요약 캐시)

### 보안/운영
- 백엔드 통한 안전한 AI 설정 전달 (`/v1/keys/ai`, HMAC 서명)
- `xcconfig` 기반 로컬 폴백 설정
- 업데이트 정책 조회 (`/v1/app/update-policy`)
- 선택형 메트릭 전송 (`/v1/metrics`)

### 광고 (옵션)
- Google Mobile Ads 통합
- 요약/리더 시트의 배너 슬롯
- 스키밍 흐름의 보상형 인터스티셜 준비
- 광고 유닛 ID 미설정 또는 테스트/플레이스홀더 ID인 경우 자동 스킵

## 기술 스택

### iOS 앱
- SwiftUI + Core Data
- Swift 5.9+
- ActivityKit (Live Activity)
- UserNotifications
- GoogleMobileAds SDK

### 백엔드 (`server/`)
- FastAPI (Python 3.11+)
- HTTPS + HMAC 서명
- AI 키 전달, Notion OAuth finalize, 메트릭, 업데이트 정책 API

## 프로젝트 구조

```text
.
├── Isla Reader/                       # iOS 앱 소스
│   ├── Views/
│   ├── Models/
│   ├── Utils/
│   ├── Assets.xcassets/
│   ├── *.lproj/                       # en/zh-Hans/ja/ko
│   └── Isla_Reader.xcdatamodeld/
├── Isla ReaderTests/                  # 단위 테스트 (Swift Testing)
├── Isla ReaderUITests/                # UI 테스트 (XCTest)
├── scripts/                           # 개발/빌드/테스트 스크립트
├── server/                            # 선택형 보안 백엔드
├── README.md
└── README_CN.md
```

## 빠른 시작

### 요구 사항
- Xcode 15+
- iOS Simulator 런타임 (권장: `iPhone 16`; 기기 인자를 생략하면 기본값은 `iPhone 15 Pro`)
- macOS 커맨드라인 도구
- 백엔드 사용 시: Python 3.11+

### 1) 클론 및 열기

```bash
git clone <your-repo-url>
cd LanRead-ios
open "Isla Reader.xcodeproj"
```

### 2) 시크릿 설정

기본 설정은 이미 커밋됨:
- `Config/Base.xcconfig`

로컬 오버라이드( gitignore ):

```bash
cp Config/AISecrets.xcconfig.example Config/AISecrets.xcconfig
```

권장 구성:
- `SECURE_SERVER_BASE_URL`, `SECURE_SERVER_CLIENT_ID`, `SECURE_SERVER_CLIENT_SECRET`, `SECURE_SERVER_REQUIRE_TLS` 설정
- `api_endpoint`, `model`, `api_key`는 백엔드에서 전달

로컬 폴백:
- `AI_API_ENDPOINT`, `AI_MODEL`, `AI_API_KEY` 설정

### 3) 빌드 및 실행

```bash
./scripts/dev.sh "iPhone 16"
```

## 개발 명령어

```bash
# build
./scripts/build.sh debug
./scripts/build.sh release
./scripts/build.sh clean

# run + logs
./scripts/run.sh "iPhone 16"

# one-step dev
./scripts/dev.sh "iPhone 16"

# 시뮬레이터 앱 데이터 유지
./scripts/dev_preserve_data.sh "iPhone 16"

# tests
xcodebuild test -project "Isla Reader.xcodeproj" -scheme "LanRead" -destination 'platform=iOS Simulator,name=iPhone 16'

# checks
./scripts/test-localization.sh
./scripts/test-epub-parser.sh
./scripts/test-scripts.sh

# app-review preflight
./scripts/preflight-app-review.sh
./scripts/preflight-app-review.sh --full
```

## 선택형 백엔드 최소 실행

```bash
cd server
python -m venv .venv
source .venv/bin/activate
pip install -e .
cp .env.example .env
uvicorn app.main:app --host 0.0.0.0 --port 8443 --no-access-log --ssl-keyfile certs/server.key --ssl-certfile certs/server.crt
```

자세한 내용은 [server/README.md](server/README.md) 참고.

## 개인정보

- 핵심 읽기 데이터는 기본적으로 기기 로컬에 저장됩니다(Core Data + EPUB 파일).
- AI/Notion 동기화에는 네트워크가 필요합니다.
- 로컬 읽기 기능은 계정이 필요 없습니다.
- 설정에서 내보내기/가져오기/초기화를 직접 수행할 수 있습니다.

## 관련 문서

- 요구사항: [Isla Reader/docs/requirements.md](Isla%20Reader/docs/requirements.md)
- 읽기 상호작용 설계: [Isla Reader/docs/reading_interaction_design.md](Isla%20Reader/docs/reading_interaction_design.md)
- 프롬프트 전략: [Isla Reader/docs/prompt_strategy.md](Isla%20Reader/docs/prompt_strategy.md)
- Notion OAuth 설정: [Isla Reader/docs/NOTION_OAUTH_SETUP.md](Isla%20Reader/docs/NOTION_OAUTH_SETUP.md)
- 스크립트 가이드: [scripts/README.md](scripts/README.md)

## 라이선스

MIT. 자세한 내용은 [LICENSE](LICENSE).
