# LanRead - Lecteur EPUB iOS avec IA

[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20iPadOS-lightgrey.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

LanRead est une application de lecture SwiftUI, centrée sur EPUB, l'assistance IA et un stockage local-first.

## Langues du README

- English: [README.md](README.md)
- 中文: [README_CN.md](README_CN.md)
- 日本語: [README_JA.md](README_JA.md)
- 한국어: [README_KO.md](README_KO.md)
- Español: [README_ES.md](README_ES.md)
- Deutsch: [README_DE.md](README_DE.md)
- Français: [README_FR.md](README_FR.md)

## État actuel (fidèle au code)

- Plateforme cible: iOS/iPadOS 16.0+
- Marketing Version dans Xcode: `1.0.5`
- Format d'import principal: `EPUB` via l'app Fichiers
- Langues UI intégrées: anglais, chinois simplifié, japonais, coréen
- Simulateur par défaut des scripts (sans argument): `iPhone 15 Pro`

## Progrès récents (snapshot 2026-03)

- Améliorations de stabilité du reader: gestion de sélection, interactions en bord de page, et prévention du drift horizontal.
- Workflow des surlignages renforcé: fusion multi-sélection, édition de note améliorée, fallback d'export pour cartes image trop grandes.
- Interaction IA améliorée: saisie Ask AI auto-redimensionnable en multi-lignes, ordre harmonisé traduire/expliquer/questionner.
- Métriques affinées: fenêtres 7 jours/semaine/mois alignées sur le fuseau local, compteurs séparés summary vs skimming.
- Flow skimming peaufiné: timing interstitiel ajusté aux transitions de chapitre avec messages de disponibilité plus clairs.

## Snapshot de validation (2026-03-31)

- `Isla ReaderTests`: 17 fichiers de tests, 59 cas `@Test`.
- `Isla ReaderUITests`: 2 fichiers de smoke tests UI.
- `server/tests`: 5 fichiers pytest backend.

## Fonctionnalités implémentées

### Lecture et bibliothèque
- Import EPUB (détection des doublons par checksum SHA-256)
- Recherche bibliothèque, favoris et filtres par statut de lecture
- Fiche livre (métadonnées, infos fichier, progression)
- Fusion multi-sélection des surlignages et export d'image de partage
- Lecteur avec:
  - table des matières
  - changement de page tap/swipe
  - état de pagination par chapitre
  - réglages thème/typographie
  - marque-pages (ajout/suppression/liste)
  - surlignages et notes
  - navigation vers l'emplacement d'origine d'un surlignage

### Fonctions IA
- Résumé IA au démarrage de lecture (cache Core Data)
- Affichage du résumé en style streaming
- Actions IA sur texte sélectionné/surlignage:
  - traduire
  - expliquer
  - poser une question
- Insertion du résultat IA dans les notes de surlignage
- Mode skimming:
  - résumé IA par chapitre
  - structure, phrases clés, mots-clés, questions de vérification
  - saut direct du skimming vers la position correspondante du lecteur

### Progression, rappels, Live Activity
- Tableau de bord de progression (semaine/mois/année)
- Statistiques de temps de lecture et d'atteinte d'objectif
- Rappel quotidien de lecture (notification)
- Mise à jour Live Activity de la progression quotidienne (iOS 16.1+)

### Sync et gestion des données
- Flux OAuth Notion
- Initialisation de la bibliothèque Notion (choix page parente, création base)
- Moteur de sync en file avec retry/backoff pour changements surlignages/notes
- Export/import des données de lecture (JSON, sans fichiers de livres)
- Visualisation et nettoyage du cache
- Réinitialisation complète locale (Core Data + EPUB importés + cache IA)

### Sécurité et exploitation
- Récupération sécurisée de la config IA via backend (`/v1/keys/ai`, signé HMAC)
- Fallback local endpoint/modèle/clé via `xcconfig`
- Récupération de la politique de mise à jour (`/v1/app/update-policy`)
- Reporting métriques optionnel (`/v1/metrics`)

### Publicités (optionnel)
- Intégration Google Mobile Ads
- Emplacements bannière dans les écrans résumé/reader
- Préparation d'interstitiels récompensés dans le flux skimming
- Requêtes pub ignorées automatiquement si IDs absents ou IDs test/placeholder

## Stack technique

### App iOS
- SwiftUI + Core Data
- Swift 5.9+
- ActivityKit (Live Activity)
- UserNotifications
- GoogleMobileAds SDK

### Backend (`server/`)
- FastAPI (Python 3.11+)
- HTTPS + signature HMAC
- Endpoints pour distribution clé IA, finalize OAuth Notion, métriques et politique de mise à jour

## Structure du projet

```text
.
├── Isla Reader/                       # code source iOS
│   ├── Views/
│   ├── Models/
│   ├── Utils/
│   ├── Assets.xcassets/
│   ├── *.lproj/                       # en/zh-Hans/ja/ko
│   └── Isla_Reader.xcdatamodeld/
├── Isla ReaderTests/                  # tests unitaires (Swift Testing)
├── Isla ReaderUITests/                # tests UI (XCTest)
├── scripts/                           # scripts dev/build/test
├── server/                            # backend sécurisé optionnel
├── README.md
└── README_CN.md
```

## Démarrage rapide

### Prérequis
- Xcode 15+
- Runtime iOS Simulator (recommandé: `iPhone 16`; sans paramètre appareil, les scripts utilisent `iPhone 15 Pro`)
- Outils en ligne de commande macOS
- Optionnel backend: Python 3.11+

### 1) Cloner et ouvrir

```bash
git clone <your-repo-url>
cd LanRead-ios
open "Isla Reader.xcodeproj"
```

### 2) Configurer les secrets

Configuration de base déjà commitée:
- `Config/Base.xcconfig`

Override local optionnel (gitignored):

```bash
cp Config/AISecrets.xcconfig.example Config/AISecrets.xcconfig
```

Configuration recommandée:
- renseigner `SECURE_SERVER_BASE_URL`, `SECURE_SERVER_CLIENT_ID`, `SECURE_SERVER_CLIENT_SECRET`, `SECURE_SERVER_REQUIRE_TLS`
- récupérer `api_endpoint`, `model`, `api_key` depuis le backend

Fallback local:
- renseigner `AI_API_ENDPOINT`, `AI_MODEL`, `AI_API_KEY`

### 3) Build et exécution

```bash
./scripts/dev.sh "iPhone 16"
```

## Commandes de développement

```bash
# build
./scripts/build.sh debug
./scripts/build.sh release
./scripts/build.sh clean

# exécuter sur simulateur + logs
./scripts/run.sh "iPhone 16"

# flux complet
./scripts/dev.sh "iPhone 16"

# conserver les données app du simulateur
./scripts/dev_preserve_data.sh "iPhone 16"

# tests
xcodebuild test -project "Isla Reader.xcodeproj" -scheme "LanRead" -destination 'platform=iOS Simulator,name=iPhone 16'

# checks
./scripts/test-localization.sh
./scripts/test-epub-parser.sh
./scripts/test-scripts.sh

# pré-vérification App Review
./scripts/preflight-app-review.sh
./scripts/preflight-app-review.sh --full
```

## Backend optionnel (quick start)

```bash
cd server
python -m venv .venv
source .venv/bin/activate
pip install -e .
cp .env.example .env
uvicorn app.main:app --host 0.0.0.0 --port 8443 --no-access-log --ssl-keyfile certs/server.key --ssl-certfile certs/server.crt
```

Détails: [server/README.md](server/README.md)

## Confidentialité

- Les données de lecture sont stockées localement par défaut (Core Data + EPUB locaux).
- Les fonctions IA et sync Notion nécessitent le réseau.
- Aucun compte requis pour les fonctions locales de lecture.
- Export/import/reset disponibles dans Réglages.

## Documentation associée

- Exigences: [Isla Reader/docs/requirements.md](Isla%20Reader/docs/requirements.md)
- Design d'interaction lecture: [Isla Reader/docs/reading_interaction_design.md](Isla%20Reader/docs/reading_interaction_design.md)
- Stratégie de prompts: [Isla Reader/docs/prompt_strategy.md](Isla%20Reader/docs/prompt_strategy.md)
- Setup Notion OAuth: [Isla Reader/docs/NOTION_OAUTH_SETUP.md](Isla%20Reader/docs/NOTION_OAUTH_SETUP.md)
- Guide scripts: [scripts/README.md](scripts/README.md)

## Licence

MIT. Voir [LICENSE](LICENSE).
