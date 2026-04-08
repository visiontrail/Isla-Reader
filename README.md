# LanRead - AI-Powered EPUB Reader for iOS

[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20iPadOS-lightgrey.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

LanRead is a SwiftUI reading app focused on EPUB reading, AI-assisted understanding, and private local-first data.

## README Languages

- English: [README.md](README.md)
- 中文: [README_CN.md](README_CN.md)
- 日本語: [README_JA.md](README_JA.md)
- 한국어: [README_KO.md](README_KO.md)
- Español: [README_ES.md](README_ES.md)
- Deutsch: [README_DE.md](README_DE.md)
- Français: [README_FR.md](README_FR.md)

## Current Status (Code-Accurate)

- App target: iOS/iPadOS 16.0+
- Current marketing version in Xcode project: `1.0.5`
- Primary format support: `EPUB` import from Files app
- UI localizations in app bundle: English, Simplified Chinese, Japanese, Korean
- Script default simulator (when no argument is passed): `iPhone 15 Pro`

## Recent Progress (2026-03 Snapshot)

- Reader stability updates around selection handling, page-edge interactions, and horizontal drift prevention.
- Highlight workflow upgrades: multi-select merge, dedicated note editor behavior, and share-image export fallback for oversized cards.
- AI interaction updates: multiline auto-resizing Ask-AI input and aligned action ordering for translate/explain/ask flows.
- Metrics refinement: local-timezone window alignment (7-day/week/month) and split counters for summary vs skimming reader/AI events.
- Skimming flow polish: interstitial timing tuned to chapter transitions with clearer readiness notices.

## Validation Snapshot (2026-03-31)

- `Isla ReaderTests`: 17 test files, 59 `@Test` cases.
- `Isla ReaderUITests`: 2 UI smoke-test files.
- `server/tests`: 5 backend pytest files.

## What Is Implemented

### Reading and Library
- EPUB import (with duplicate detection by SHA-256 checksum)
- Library search, favorite flag, and status filters (`Want to Read`, `Reading`, `Paused`, `Finished`)
- Book details panel (metadata, file info, progress)
- Highlight multi-select merge and share-image card export
- Reader with:
  - table of contents
  - tap/swipe page turning
  - per-chapter pagination state
  - reading theme/typography controls
  - bookmark add/delete and bookmark list
  - text highlights and notes
  - highlight jump-back navigation

### AI Features
- AI start-reading summary (cached to Core Data)
- Streaming-style summary rendering in UI
- Inline AI actions on selected text/highlights:
  - translate
  - explain
  - ask question
- AI output can be inserted into highlight notes
- Skimming mode:
  - chapter-by-chapter AI summaries
  - structure points, key sentences, keywords, guiding questions
  - jump from skimming directly into full reader location

### Progress, Reminder, and Live Activity
- Reading progress dashboard (week/month/year)
- Reading time and goal achievement stats
- Daily reading reminder notifications
- Live Activity updates for daily reading progress (iOS 16.1+)

### Sync and Data Management
- Notion OAuth connection flow
- Notion library initialization (choose parent page, create database)
- Queue-based sync engine with retry/backoff for highlights/notes changes
- Data export/import for reading data (JSON, excluding book files)
- Cache usage inspection and cache cleanup
- Full local data reset (Core Data + imported book files + cached summaries)

### Security and Operations
- Secure AI config fetch via backend (`/v1/keys/ai`, HMAC signed)
- Local fallback for AI endpoint/model/key via `xcconfig`
- App update prompt policy fetch (`/v1/app/update-policy`)
- Optional metrics reporting to backend (`/v1/metrics`)

### Ads (Optional by Config)
- Google Mobile Ads integration
- Banner slots in summary/reader sheets
- Rewarded interstitial preparation in skimming flow
- Ad requests are skipped automatically when ad unit IDs are missing or placeholder/test IDs

## Tech Stack

### iOS App
- SwiftUI + Core Data
- Swift 5.9+
- ActivityKit (Live Activity)
- UserNotifications
- GoogleMobileAds SDK

### Backend (`server/`)
- FastAPI (Python 3.11+)
- HTTPS + HMAC request signing
- Endpoints for AI key delivery, Notion OAuth finalize, metrics, and update policy

## Project Structure

```text
.
├── Isla Reader/                       # iOS app source
│   ├── Views/                         # SwiftUI screens
│   ├── Models/                        # Core Data entities/extensions
│   ├── Utils/                         # Services (AI, Notion, reminders, cache, etc.)
│   ├── Assets.xcassets/
│   ├── *.lproj/                       # app UI localizations (en/zh-Hans/ja/ko)
│   └── Isla_Reader.xcdatamodeld/
├── Isla ReaderTests/                  # unit tests (Swift Testing)
├── Isla ReaderUITests/                # UI smoke tests (XCTest)
├── scripts/                           # local dev/build/test scripts
├── server/                            # optional secure backend
├── README.md
└── README_CN.md
```

## Quick Start

### Requirements
- Xcode 15+
- iOS Simulator runtime (recommended device: `iPhone 16`; scripts default to `iPhone 15 Pro` when omitted)
- macOS with command line tools
- Optional for backend: Python 3.11+

### 1) Clone and open

```bash
git clone <your-repo-url>
cd LanRead-ios
open "Isla Reader.xcodeproj"
```

### 2) Configure app secrets

Base config is already committed:
- `Config/Base.xcconfig`

Optional local override (gitignored):

```bash
cp Config/AISecrets.xcconfig.example Config/AISecrets.xcconfig
```

Recommended production-style setup:
- Fill secure server values (`SECURE_SERVER_BASE_URL`, `SECURE_SERVER_CLIENT_ID`, `SECURE_SERVER_CLIENT_SECRET`, `SECURE_SERVER_REQUIRE_TLS`)
- Let backend return `api_endpoint`, `model`, `api_key`
- Fill AdMob unit IDs (`ADMOB_BANNER_AD_UNIT_ID`, `ADMOB_INTERSTITIAL_AD_UNIT_ID`, `ADMOB_REWARDED_INTERSTITIAL_AD_UNIT_ID`)
- Keep `ADMOB_ENABLE_REWARDED_INTERSTITIAL_FALLBACK = NO` until the rewarded-interstitial unit has been verified on a physical-device/archive build

Fallback local-only setup:
- Fill `AI_API_ENDPOINT`, `AI_MODEL`, `AI_API_KEY`

### 3) Build and run

```bash
./scripts/dev.sh "iPhone 16"
```

## Development Commands

```bash
# build only
./scripts/build.sh debug
./scripts/build.sh release
./scripts/build.sh clean

# run built app on simulator + tail logs
./scripts/run.sh "iPhone 16"

# one-step build + run
./scripts/dev.sh "iPhone 16"

# preserve installed app data in simulator
./scripts/dev_preserve_data.sh "iPhone 16"

# unit + UI tests
xcodebuild test -project "Isla Reader.xcodeproj" -scheme "LanRead" -destination 'platform=iOS Simulator,name=iPhone 16'

# helper checks
./scripts/test-localization.sh
./scripts/test-epub-parser.sh
./scripts/test-scripts.sh

# app review preflight
./scripts/preflight-app-review.sh
./scripts/preflight-app-review.sh --full
```

## Batch Automation CLI (Internal)

```bash
# single EPUB
swift run lanread-batch generate \
  --epub "Test Files/pg77090-images-3.epub" \
  --output "build/batch-single"

# batch directory (recursive scan)
swift run lanread-batch generate \
  --input-dir "/path/to/epubs" \
  --output "build/batch-output"

# wrapper script for directory mode
./scripts/batch-generate.sh --input-dir "/path/to/epubs"

# P7 reserved command stubs (interface validation only)
swift run lanread-batch captions --manifest "build/batch-single/<book-slug>/manifest.json"
swift run lanread-batch publish --manifest "build/batch-single/<book-slug>/manifest.json" --channel xiaohongshu
```

Directory mode writes an aggregated summary at `output_root/batch.summary.json`.  
Single-book artifacts remain under `output_root/<book-slug>/`.

## Optional Backend Quick Start

```bash
cd server
python -m venv .venv
source .venv/bin/activate
pip install -e .
cp .env.example .env
uvicorn app.main:app --host 0.0.0.0 --port 8443 --no-access-log --ssl-keyfile certs/server.key --ssl-certfile certs/server.crt
```

See full server deployment/security details in [server/README.md](server/README.md).

## Privacy Notes

- Core reading data is stored locally on device (Core Data + local EPUB files).
- AI calls and Notion sync require network.
- Before any AI request is sent, LanRead asks for explicit consent and discloses the current third-party AI provider in-app.
- AI permission and provider details are always available in `Settings > AI Data & Privacy`.
- No account is required for local reading features.
- You control export/import/reset from Settings.

## Related Docs

- iOS docs: [Isla Reader/docs/requirements.md](Isla%20Reader/docs/requirements.md)
- Reading interaction design: [Isla Reader/docs/reading_interaction_design.md](Isla%20Reader/docs/reading_interaction_design.md)
- Prompt strategy: [Isla Reader/docs/prompt_strategy.md](Isla%20Reader/docs/prompt_strategy.md)
- Notion OAuth setup: [Isla Reader/docs/NOTION_OAUTH_SETUP.md](Isla%20Reader/docs/NOTION_OAUTH_SETUP.md)
- Scripts guide: [scripts/README.md](scripts/README.md)

## License

MIT. See [LICENSE](LICENSE).
