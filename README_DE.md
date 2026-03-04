# LanRead - AI-gestützter EPUB-Reader für iOS

[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20iPadOS-lightgrey.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

LanRead ist eine SwiftUI-Lese-App mit Fokus auf EPUB, KI-gestütztem Verständnis und lokal-first Datenspeicherung.

## README-Sprachen

- English: [README.md](README.md)
- 中文: [README_CN.md](README_CN.md)
- 日本語: [README_JA.md](README_JA.md)
- 한국어: [README_KO.md](README_KO.md)
- Español: [README_ES.md](README_ES.md)
- Deutsch: [README_DE.md](README_DE.md)
- Français: [README_FR.md](README_FR.md)

## Aktueller Stand (codegenau)

- Zielplattform: iOS/iPadOS 16.0+
- Marketing Version im Xcode-Projekt: `1.0`
- Haupt-Importformat: `EPUB` über die Dateien-App
- In-App-UI-Sprachen: Englisch, Vereinfachtes Chinesisch, Japanisch, Koreanisch

## Implementierte Funktionen

### Lesen und Bibliothek
- EPUB-Import (Duplikaterkennung per SHA-256-Checksumme)
- Bibliothekssuche, Favoriten, Filter nach Lesestatus
- Buch-Detailansicht (Metadaten, Dateiinformationen, Fortschritt)
- Reader mit:
  - Inhaltsverzeichnis
  - Seitenwechsel per Tap/Swipe
  - Kapitelbezogenem Paging-Status
  - Theme-/Typografie-Einstellungen
  - Lesezeichen (hinzufügen/löschen/listen)
  - Highlights und Notizen
  - Sprung zur Originalposition eines Highlights

### KI-Funktionen
- KI-Startzusammenfassung (in Core Data gecacht)
- Streaming-artige Darstellung der Zusammenfassung
- KI-Aktionen auf Auswahltext/Highlight:
  - Übersetzen
  - Erklären
- KI-Ausgabe in Highlight-Notizen einfügen
- Skimming-Modus:
  - Kapitelweise KI-Zusammenfassungen
  - Strukturpunkte, Schlüsselsätze, Keywords, Prüfungsfragen
  - Direkter Sprung vom Skimming in die entsprechende Leseposition

### Fortschritt, Erinnerung, Live Activity
- Fortschritts-Dashboard (Woche/Monat/Jahr)
- Statistiken zu Lesezeit und Zielerreichung
- Tägliche Leseerinnerung per Notification
- Live-Activity-Updates für den Tagesfortschritt (iOS 16.1+)

### Sync und Datenverwaltung
- Notion-OAuth-Verbindung
- Notion-Bibliotheksinitialisierung (Parent-Page wählen, Datenbank erstellen)
- Queue-basierte Synchronisation mit Retry/Backoff für Highlight-/Notizänderungen
- Export/Import von Lesedaten (JSON, ohne Buchdateien)
- Cache-Nutzung anzeigen und Cache bereinigen
- Vollständiger lokaler Daten-Reset (Core Data + importierte EPUBs + Summary-Cache)

### Sicherheit und Betrieb
- Sicherer KI-Config-Fetch über Backend (`/v1/keys/ai`, HMAC-signiert)
- Lokaler Fallback für Endpoint/Model/Key via `xcconfig`
- Abruf einer Update-Policy (`/v1/app/update-policy`)
- Optionales Metrics-Reporting (`/v1/metrics`)

### Werbung (optional)
- Google Mobile Ads integriert
- Banner-Slots in Summary-/Reader-Sheets
- Vorbereitung von Rewarded Interstitials im Skimming-Flow
- Bei fehlenden oder Test-/Placeholder-Ad-IDs werden Requests automatisch übersprungen

## Tech-Stack

### iOS-App
- SwiftUI + Core Data
- Swift 5.9+
- ActivityKit (Live Activity)
- UserNotifications
- GoogleMobileAds SDK

### Backend (`server/`)
- FastAPI (Python 3.11+)
- HTTPS + HMAC-Signatur
- Endpunkte für KI-Key-Auslieferung, Notion OAuth finalize, Metrics und Update-Policy

## Projektstruktur

```text
.
├── Isla Reader/                       # iOS-Quellcode
│   ├── Views/
│   ├── Models/
│   ├── Utils/
│   ├── Assets.xcassets/
│   ├── *.lproj/                       # en/zh-Hans/ja/ko
│   └── Isla_Reader.xcdatamodeld/
├── Isla ReaderTests/                  # Unit-Tests (Swift Testing)
├── Isla ReaderUITests/                # UI-Tests (XCTest)
├── scripts/                           # Dev-/Build-/Test-Skripte
├── server/                            # optionales sicheres Backend
├── README.md
└── README_CN.md
```

## Schnellstart

### Voraussetzungen
- Xcode 15+
- iOS-Simulator-Runtime (empfohlen: `iPhone 16`)
- macOS Command Line Tools
- Optional fürs Backend: Python 3.11+

### 1) Klonen und öffnen

```bash
git clone <your-repo-url>
cd LanRead-ios
open "Isla Reader.xcodeproj"
```

### 2) Secrets konfigurieren

Basis-Konfiguration ist bereits im Repo:
- `Config/Base.xcconfig`

Optionaler lokaler Override (gitignored):

```bash
cp Config/AISecrets.xcconfig.example Config/AISecrets.xcconfig
```

Empfohlene Konfiguration:
- `SECURE_SERVER_BASE_URL`, `SECURE_SERVER_CLIENT_ID`, `SECURE_SERVER_CLIENT_SECRET`, `SECURE_SERVER_REQUIRE_TLS` setzen
- `api_endpoint`, `model`, `api_key` vom Backend beziehen

Lokaler Fallback:
- `AI_API_ENDPOINT`, `AI_MODEL`, `AI_API_KEY` setzen

### 3) Bauen und starten

```bash
./scripts/dev.sh "iPhone 16"
```

## Entwicklungsbefehle

```bash
# build
./scripts/build.sh debug
./scripts/build.sh release
./scripts/build.sh clean

# im Simulator starten + Logs
./scripts/run.sh "iPhone 16"

# One-Step Dev
./scripts/dev.sh "iPhone 16"

# App-Daten im Simulator behalten
./scripts/dev_preserve_data.sh "iPhone 16"

# Tests
xcodebuild test -project "Isla Reader.xcodeproj" -scheme "LanRead" -destination 'platform=iOS Simulator,name=iPhone 16'

# Checks
./scripts/test-localization.sh
./scripts/test-epub-parser.sh
./scripts/test-scripts.sh

# App-Review Preflight
./scripts/preflight-app-review.sh
./scripts/preflight-app-review.sh --full
```

## Optionales Backend (Quickstart)

```bash
cd server
python -m venv .venv
source .venv/bin/activate
pip install -e .
cp .env.example .env
uvicorn app.main:app --host 0.0.0.0 --port 8443 --no-access-log --ssl-keyfile certs/server.key --ssl-certfile certs/server.crt
```

Details: [server/README.md](server/README.md)

## Datenschutz

- Lesedaten werden standardmäßig lokal gespeichert (Core Data + lokale EPUB-Dateien).
- KI- und Notion-Sync-Funktionen benötigen Netzwerk.
- Für lokale Lesefunktionen ist kein Konto erforderlich.
- Export/Import/Reset in den Einstellungen verfügbar.

## Verwandte Dokumente

- Anforderungen: [Isla Reader/docs/requirements.md](Isla%20Reader/docs/requirements.md)
- Reading Interaction Design: [Isla Reader/docs/reading_interaction_design.md](Isla%20Reader/docs/reading_interaction_design.md)
- Prompt-Strategie: [Isla Reader/docs/prompt_strategy.md](Isla%20Reader/docs/prompt_strategy.md)
- Notion OAuth Setup: [Isla Reader/docs/NOTION_OAUTH_SETUP.md](Isla%20Reader/docs/NOTION_OAUTH_SETUP.md)
- Skript-Doku: [scripts/README.md](scripts/README.md)

## Lizenz

MIT. Siehe [LICENSE](LICENSE).
