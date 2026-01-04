# IslaBooks - AI-Powered Reading Companion

[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20iPadOS-lightgrey.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.1.2-green.svg)](CHANGELOG.md)

> Transform every book into a conversational mentor: acquire, read, understand, and discuss—all in one place.

## Overview

IslaBooks is an intelligent e-book reading application for iOS and iPadOS that leverages AI technology to enhance the reading experience. It addresses common challenges in digital reading: difficulty in acquisition, comprehension barriers, incomplete reading, poor retention, and lack of discussion partners.

### Key Features

- 📚 **Local Book Import**: Import ePub and plain text files from local storage or Files app
- 🤖 **AI-Powered Summaries**: Instant book summaries upon opening
- 🧭 **Skimming Mode**: Chapter skeleton summaries and fast navigation
- 💬 **Conversational Reading Assistant**: Ask questions about selected text, chapters, or entire books
- 🎯 **Comprehension Diagnostics**: Auto-generated quizzes to assess understanding
- 🔖 **Advanced Reader**: Bookmarks, highlights, annotations, search, and customizable themes
- ☁️ **iCloud Sync**: Seamless synchronization across devices via CloudKit
- 🔗 **Notion Sync**: Export bookmarks and highlights to Notion
- 🌙 **Reading Modes**: Night mode, adjustable fonts, line spacing, and layout settings
- 🔒 **Privacy-First**: No registration required, local-first approach with optional cloud sync

## Vision

**Make every book a conversational mentor.**

IslaBooks reimagines the reading experience by combining traditional e-reading capabilities with AI-powered understanding tools, enabling readers to not just consume content, but actively engage with and comprehend complex materials.

## Target Audience

### Learning-Oriented Readers
- Students and professionals seeking efficient knowledge acquisition
- Individuals who need to understand and summarize complex materials
- Readers who benefit from interactive learning and comprehension checks

### Casual Readers
- Users seeking personalized book recommendations
- Readers who want quick summaries before diving deep
- Those who value comfortable, distraction-free reading experiences

## Core Capabilities

### 1. Book Management
- Import books from Files app, iCloud Drive, or local storage
- Support for ePub and plain text formats
- Organize books with custom tags and categories
- Reading progress tracking and statistics
- Search and filter across library

### 2. AI-Enhanced Reading

#### Instant Summaries
- Book overview with key points and chapter structure
- Chapter summaries with main concepts
- Automatic caching for offline access
- Manual refresh option

#### Interactive Q&A
- **Selection-based queries**: Highlight text to translate, explain, or elaborate
- **Chapter-level questions**: Ask about themes, concepts, or arguments
- **Book-level discussions**: Cross-reference ideas across chapters
- **Citation support**: All answers include references to source material

### 3. Comprehension Tools

#### Understanding Diagnostics
- Auto-generated quizzes (2-5 questions) upon opening new books
- Instant feedback with detailed explanations
- Learning path recommendations based on results

#### Knowledge Cards
- One-click conversion of highlights and notes to flashcards
- AI-powered glossary with definitions and examples
- Export to Markdown/CSV for review systems

### 4. Reading Experience

#### Core Reader Features
- Table of contents navigation
- Full-text search
- Bookmarks and progress tracking
- Highlights with custom colors
- Inline annotations
- Reading statistics

#### Customization
- Multiple themes (light, dark, sepia, custom)
- Adjustable font size and typeface
- Configurable line spacing and margins
- Night mode with blue light reduction

### 5. Sync & Privacy

#### iCloud Integration
- Automatic sync via CloudKit (no app registration required)
- Syncs: reading progress, bookmarks, highlights, notes, settings
- Optional: disable cloud sync for local-only storage
- One-tap cloud data deletion

#### Privacy Commitment
- Minimal data collection
- No third-party analytics or tracking
- User owns all imported content
- AI requests are anonymized
- Full data export capability

## Technical Architecture

### Client
- **Platform**: iOS 16.0+, iPadOS 16.0+
- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI
- **Storage**: Core Data + iCloud CloudKit

### AI Integration
- **Model**: OpenAI-compatible API (configurable)
- **Streaming**: Progressive UI updates (simulated streaming); SSE planned
- **Context Management**: Rule-based paragraph extraction (no vector DB)
- **Caching**: Aggressive summary and response caching

### Data Synchronization
- **Service**: CloudKit Private Database
- **Scope**: User library, progress, annotations, preferences
- **Conflict Resolution**: Last-write-wins with timestamp
- **Offline Support**: Full offline reading with sync on reconnection

## Installation

### Requirements
- iOS 16.0+ or iPadOS 16.0+
- Xcode 15.0+
- Swift 5.9+
- Active Apple Developer account (for CloudKit)

### Setup

1. **Clone the repository**
```bash
git clone https://github.com/yourusername/IslaBooks-ios.git
cd IslaBooks-ios/Isla\ Reader
```

2. **Open in Xcode**
```bash
open Isla\ Reader.xcodeproj
```

3. **Configure CloudKit**
   - Enable iCloud capability in project settings
   - Select CloudKit container
   - Ensure "CloudKit" is enabled in Signing & Capabilities

4. **Configure AI & secure server**
   - Copy `Config/AISecrets.xcconfig.example` to `Config/AISecrets.xcconfig`
   - Set `AI_API_ENDPOINT` and `AI_MODEL`
   - Choose one of:
     - Local only: set `AI_API_KEY`
     - Secure server: leave `AI_API_KEY` empty and set `SECURE_SERVER_BASE_URL`, `SECURE_SERVER_CLIENT_ID`, `SECURE_SERVER_CLIENT_SECRET`, `SECURE_SERVER_REQUIRE_TLS`

5. **Build and Run**
   - Select target device or simulator
   - Press `Cmd + R` to build and run

### Secure key exchange server

- Backend lives in `server/` (FastAPI + HMAC + HTTPS). See `server/README.md` for full instructions.
- Quick start: `cd server && python -m venv .venv && source .venv/bin/activate && pip install -e .`
- Copy `.env.example` to `.env`, set `ISLA_API_KEY`, `ISLA_CLIENT_ID`, `ISLA_CLIENT_SECRET`, and run `uvicorn app.main:app --host 0.0.0.0 --port 8443 --ssl-keyfile certs/server.key --ssl-certfile certs/server.crt`.

## Usage

### Quick Start

1. **Import Your First Book**
   - Tap "+" on the bookshelf
   - Select an ePub or .txt file from Files app
   - Book appears in your library

2. **Read with AI Assistance**
   - Tap the book to open reader
   - View AI-generated summary on first page
   - Select any text to ask questions, translate, or get explanations

3. **Skimming mode**
   - Long-press to show chapter summaries
   - Swipe left/right to navigate chapters

4. **Track Progress**
   - Bookmarks auto-save
   - Progress syncs across devices via iCloud
   - View reading statistics in "My Library"

### Advanced Features

#### Custom AI Actions
Configure preset actions for text selection:
- Translate to [language]
- Explain this concept
- Provide examples
- Compare with [concept]
- Summarize in simple terms

#### Export & Backup
- Export highlights and notes as Markdown
- Export knowledge cards as CSV
- Backup library to Files app


## Roadmap

### v0.1 MVP (Current)
- [x] Local file import (ePub, plain text)
- [x] Basic ePub rendering engine
- [x] Reader essentials (TOC, bookmarks, progress, themes)
- [x] AI book summaries with caching
- [x] Skimming mode (chapter summaries with jump)


### v0.2 (MVP Release)
- [ ] Performance optimization
- [ ] Stability improvements
- [ ] Compliance and cost governance
- [ ] App Store submission

### v0.5 (Planned)
- [ ] Selection-based Q&A (translate, explain, summarize)
- [ ] Minimal iCloud sync (progress only)

### v1.0 (Future)

## Development

### Project Structure

```
Isla Reader/
├── Isla Reader/
│   ├── Isla_ReaderApp.swift       # App entry point
│   ├── ContentView.swift          # Main view
│   ├── Models/                    # Data models
│   ├── Views/                     # SwiftUI views
│   ├── Utils/                     # Utilities and services
│   ├── Persistence.swift          # Core Data stack
│   ├── Isla_Reader.xcdatamodeld/  # Core Data model
│   ├── en.lproj/                  # English localization
│   ├── zh-Hans.lproj/             # Simplified Chinese localization
│   ├── ja.lproj/                  # Japanese localization
│   ├── ko.lproj/                  # Korean localization
│   ├── Info.plist                 # App configuration
│   ├── Isla_Reader.entitlements   # App entitlements
│   ├── docs/                      # App-specific docs
│   └── Assets.xcassets/           # Images and colors
├── Isla Reader.xcodeproj/         # Xcode project
├── Isla ReaderTests/              # Unit tests
├── Isla ReaderUITests/            # UI tests
├── scripts/                       # Build and automation scripts
└── server/                        # Secure key exchange server (FastAPI)
```

### Building for Development

```bash
# Run all tests
xcodebuild test -project "Isla Reader.xcodeproj" -scheme "Isla Reader" -destination 'platform=iOS Simulator,name=iPhone 16'

# Build for simulator
xcodebuild build -project "Isla Reader.xcodeproj" -scheme "Isla Reader" -destination 'platform=iOS Simulator,name=iPhone 16'

# Build for device
xcodebuild build -project "Isla Reader.xcodeproj" -scheme "Isla Reader" -destination 'generic/platform=iOS'
```

### Testing

```bash
# Run unit tests
cd scripts
./test-scripts.sh

# Run in simulator
./simulator.sh
```

## Compliance & Privacy

### App Store Guidelines
- **5.1 Privacy**: Minimal data collection, privacy policy provided, data deletion available
- **5.1.1 Permissions**: All permissions requested with clear purpose descriptions
- **5.1.3 Account Deletion**: In-app account deletion with server-side data removal
- **3.1 Payments**: IAP for any digital content/features (if applicable)
- **4.2 Quality**: Complete functionality, no crashes, production-ready

### Privacy Features
- No email or personal identification collected
- iCloud used only for data sync (optional)
- AI requests anonymized and not logged
- User controls all data with export/delete options
- Compliant with App Privacy Nutrition Label requirements

### Copyright & Content
- **User Responsibility**: Users are responsible for imported content legality
- **No External Sources**: App does not provide book downloads or aggregation
- **Public Domain**: Example books should be from Project Gutenberg or similar
- **Attribution**: All AI-generated content includes source citations

## Contributing

We welcome contributions! Please read our [Contributing Guidelines](CONTRIBUTING.md) before submitting pull requests.

### Development Setup
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Code Style
- Follow Swift API Design Guidelines
- Use SwiftLint for code consistency
- Write tests for new features
- Update documentation as needed

## Support

### Documentation
- [Quick Start](scripts/QUICK_START.md)
- [Requirements Specification](Isla%20Reader/docs/requirements.md)
- [Reading Interaction Design](Isla%20Reader/docs/reading_interaction_design.md)
- [Prompt Strategy](Isla%20Reader/docs/prompt_strategy.md)


## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Inspired by the vision of making knowledge more accessible through AI
- Built with SwiftUI and Core Data
- AI integration via OpenAI-compatible APIs
- Special thanks to the open-source community

## Changelog

Changelog will be published in Releases. For current progress, see Roadmap above.

---

**Current Version**: v1.0
**Last Updated**: December 12, 2025  
**Status**: Active Development (MVP Phase)

Made with ❤️ for readers who love to learn.
