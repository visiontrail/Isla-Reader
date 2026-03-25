# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
# Debug build + simulator run (most common)
./scripts/dev.sh "iPhone 16"

# Build only
./scripts/build.sh [clean|debug|release]

# Boot simulator, install, and tail logs
./scripts/run.sh "iPhone 16"

# Run all unit and UI tests (CI-style)
xcodebuild test -project "Isla Reader.xcodeproj" -scheme "LanRead" -destination 'platform=iOS Simulator,name=iPhone 16'

# Regression checks
./scripts/test-localization.sh
./scripts/test-epub-parser.sh
```

## Architecture

LanRead is a SwiftUI EPUB reader app (iOS/iPadOS 16.0+) with AI features, Notion sync, and reading analytics. Source lives in `Isla Reader/`.

**Layer structure:**
- `Views/` — SwiftUI UI entry points (9 major files, largest are `ReaderWebView.swift` and `ReaderView.swift`)
- `Models/` — Core Data entity classes (Book, LibraryItem, Highlight, Bookmark, ReadingProgress, Annotation, NotionSyncConfig, etc.)
- `Utils/` — Services: AI (`AISummaryService`, `ReadingAIService`), EPUB parsing (`EPubParser`), Notion sync, security, ads
- `Isla_Reader.xcdatamodeld/` — Core Data schema

**Reader pagination system:** CSS multi-column layout (`column-width: 100vw`, `column-gap: 0`, `column-fill: auto`) rendered in WKWebView. Page turns are programmatic JS (`window.scrollTo(index * viewportWidth, 0)`). `webView.scrollView.isScrollEnabled = false` — user touch scrolling is disabled. All selection JS is injected as a WKUserScript at document end and lives in `ReaderWebView.swift`.

**Text selection:** Native iOS handles for initial selection; JS overlay (`selectionVisualOverlay`) for cross-page continuation only. `overflow-x: hidden` prevents WebKit auto-scroll during selection. Hard lock (`setSelectionHardLock`) is set immediately on first selection establishment to prevent WebKit from auto-scrolling to the next column when the handle nears the screen edge.

**Notion sync:** Queue-based (Core Data `SyncQueue`/`SyncQueueItem`) with retry/backoff, driven by `NotionSyncEngine`.

**AI features:** Streamed summaries cached to Core Data, consent-gated, configurable via `Config/AISecrets.xcconfig` (gitignored).

## Coding Conventions

- Swift 5.9+, 4-space indentation
- `struct` for UI and data models; `final class` for services
- SwiftUI property wrappers: `@StateObject`, `@Environment`, etc.
- Types: `UpperCamelCase`; members: `lowerCamelCase`; localization keys: namespaced (`ai.summary.start_reading`)
- Break large view bodies into `private` computed properties or `@ViewBuilder` helpers
- Use `DebugLogger` instead of `print`
- Mirror every new localization key across all `*.lproj/Localizable.strings` files

## Testing

- Unit tests use Swift `Testing` package (`@Test`, `#expect`) in `Isla ReaderTests/`; name test functions after behavior (`@Test func generatesSummaryFromSelection()`)
- UI smoke tests in `Isla ReaderUITests/` — no sleeps, use shared helpers
- Manual regression documented in `TESTING_GUIDE.md`
- EPUB test fixtures in `Test Files/`

## Configuration & Secrets

- API keys via local `Config/AISecrets.xcconfig` (gitignored, never commit)
- Template: `Config/AISecrets.xcconfig.example`
- Key vars: `AI_API_ENDPOINT`, `AI_MODEL`, `AI_API_KEY`, `SECURE_SERVER_*`, `NOTION_CLIENT_ID`, `ADMOB_*_AD_UNIT_ID`

## Commits

Follow Conventional Commits: `feat(library): …`, `fix(reader): …`. Verb imperative, scoped prefix.
