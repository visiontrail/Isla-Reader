# Repository Guidelines

## Project Structure & Module Organization
The SwiftUI app lives in `Isla Reader/`, with `Views/` for UI entry points, `Models/` for Core Data-backed entities, and `Utils/` for helpers like `AISummaryService.swift`, `LocalizationHelper.swift`, and `DebugLogger.swift`. Assets stay in `Assets.xcassets`, localizations in `*.lproj/`, and schema data in `Isla_Reader.xcdatamodeld`. Logic tests reside in `Isla ReaderTests/`, UI smoke tests in `Isla ReaderUITests/`, while `Test Files/` contains EPUB fixtures and `scripts/` holds reproducible workflows.

## Build, Test, and Development Commands
- `./scripts/dev.sh "iPhone 16"` — one-step debug build plus simulator run.
- `./scripts/build.sh [clean|debug|release]` — wraps `xcodebuild`, writing artifacts to `build/` and `build.log`.
- `./scripts/run.sh "iPhone 16"` — boots the target simulator, installs the `.app`, and tails console logs.
- `xcodebuild test -project "Isla Reader.xcodeproj" -scheme "LanRead" -destination 'platform=iOS Simulator,name=iPhone 16'` — CI-friendly unit/UI test run.
- `./scripts/test-localization.sh` and `./scripts/test-epub-parser.sh` — quick regression checks for prompt localization and EPUB ingestion.

## Coding Style & Naming Conventions
Use Swift 5.9+ with four-space indentation. Prefer `struct` for UI and data models, `final class` for services, and SwiftUI property wrappers (`@StateObject`, `@Environment`) as shown in `AISummaryView`. Types use UpperCamelCase, members lowerCamelCase, localized keys stay namespaced (`ai.summary.start_reading`). Break large view bodies into `private` computed properties/`@ViewBuilder` helpers, leave inline documentation sparingly, and always log via `DebugLogger` instead of raw `print`.

## Testing Guidelines
Unit tests rely on the Swift `Testing` package (`@Test`, `#expect`); name functions after the behavior under test, e.g., `@Test func generatesSummaryFromSelection()`. Keep UI launch tests in `Isla ReaderUITests/` deterministic by avoiding sleeps and reusing shared helpers. Manual regression for the “Start Reading” journey is documented in `TESTING_GUIDE.md`. Before opening a PR, run `xcodebuild test` and rerun localization/EPUB scripts whenever prompts or import flows change.

## Commit & Pull Request Guidelines
Commits follow the Conventional Commit pattern in history (`feat(library): …`, `fix(reader): …`); keep the verb imperative and add a scoped prefix. Pull requests should reference an issue, summarize behavior changes, enumerate manual test steps (device + command), and attach screenshots for UI edits. Run `./scripts/test-scripts.sh` plus targeted tests before pushing, and call out any CloudKit/OpenAI configuration steps reviewers must perform.

## Localization & Configuration Notes
Mirror every prompt key across each `*.lproj/Localizable.strings` file and rerun `./scripts/test-localization.sh` after edits. Handle API keys and CloudKit container IDs through local Xcode configuration only; never commit credentials or bespoke `.xcconfig` files. Extend AI features through `LocalizationHelper`/`AISummaryService` so language awareness stays centralized, and record new environment toggles in `README.md`.
