# LanRead - Lector EPUB con IA para iOS

[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20iPadOS-lightgrey.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

LanRead es una app de lectura basada en SwiftUI, centrada en EPUB, comprensión asistida por IA y almacenamiento local primero.

## Idiomas del README

- English: [README.md](README.md)
- 中文: [README_CN.md](README_CN.md)
- 日本語: [README_JA.md](README_JA.md)
- 한국어: [README_KO.md](README_KO.md)
- Español: [README_ES.md](README_ES.md)
- Deutsch: [README_DE.md](README_DE.md)
- Français: [README_FR.md](README_FR.md)

## Estado actual (según el código)

- Plataforma objetivo: iOS/iPadOS 16.0+
- Marketing Version en Xcode: `1.0`
- Formato de importación principal: `EPUB` desde Files
- Idiomas UI incluidos en la app: inglés, chino simplificado, japonés, coreano

## Funcionalidades implementadas

### Lectura y biblioteca
- Importación EPUB (detección de duplicados por checksum SHA-256)
- Búsqueda en biblioteca, favoritos y filtros por estado de lectura
- Panel de detalles del libro (metadatos, archivo, progreso)
- Lector con:
  - tabla de contenidos
  - paginación por toque/deslizamiento
  - estado de paginación por capítulo
  - controles de tema y tipografía
  - marcadores (añadir/eliminar/listar)
  - resaltados y notas
  - salto a la ubicación original del resaltado

### Funciones de IA
- Resumen de inicio de lectura con IA (cacheado en Core Data)
- Renderizado estilo streaming del resumen
- Acciones IA sobre texto seleccionado/resaltado:
  - traducir
  - explicar
- Inserción de respuesta IA en notas de resaltado
- Modo skimming:
  - resumen IA por capítulo
  - estructura, frases clave, palabras clave y preguntas guía
  - salto desde skimming al punto correspondiente del lector

### Progreso, recordatorios y Live Activity
- Panel de progreso (semana/mes/año)
- Estadísticas de tiempo de lectura y cumplimiento de objetivo
- Recordatorio diario de lectura por notificación
- Actualización de Live Activity para el progreso diario (iOS 16.1+)

### Sincronización y gestión de datos
- Flujo OAuth de Notion
- Inicialización de biblioteca Notion (selección de página padre y creación de base de datos)
- Motor de sincronización en cola con reintentos/backoff para cambios en resaltados/notas
- Exportación/importación de datos de lectura (JSON, sin archivos de libros)
- Visualización y limpieza de caché
- Borrado total de datos locales (Core Data + EPUB importados + caché de resúmenes)

### Seguridad y operación
- Configuración IA segura vía backend (`/v1/keys/ai`, firmado con HMAC)
- Fallback local de endpoint/model/key por `xcconfig`
- Política de actualización remota (`/v1/app/update-policy`)
- Reporte opcional de métricas (`/v1/metrics`)

### Anuncios (opcional)
- Integración de Google Mobile Ads
- Slots de banner en resumen/hojas del lector
- Preparación de rewarded interstitial en flujo de skimming
- Si faltan IDs de anuncios o son IDs de prueba/placeholder, se omiten automáticamente

## Stack técnico

### App iOS
- SwiftUI + Core Data
- Swift 5.9+
- ActivityKit (Live Activity)
- UserNotifications
- GoogleMobileAds SDK

### Backend (`server/`)
- FastAPI (Python 3.11+)
- HTTPS + firma HMAC
- Endpoints para entrega de clave IA, finalize OAuth Notion, métricas y política de actualización

## Estructura del proyecto

```text
.
├── Isla Reader/                       # código fuente iOS
│   ├── Views/
│   ├── Models/
│   ├── Utils/
│   ├── Assets.xcassets/
│   ├── *.lproj/                       # en/zh-Hans/ja/ko
│   └── Isla_Reader.xcdatamodeld/
├── Isla ReaderTests/                  # tests unitarios (Swift Testing)
├── Isla ReaderUITests/                # pruebas UI (XCTest)
├── scripts/                           # scripts de desarrollo/build/test
├── server/                            # backend seguro opcional
├── README.md
└── README_CN.md
```

## Inicio rápido

### Requisitos
- Xcode 15+
- Runtime de iOS Simulator (recomendado: `iPhone 16`)
- macOS con herramientas de línea de comandos
- Opcional para backend: Python 3.11+

### 1) Clonar y abrir

```bash
git clone <your-repo-url>
cd LanRead-ios
open "Isla Reader.xcodeproj"
```

### 2) Configurar secretos

Configuración base ya incluida:
- `Config/Base.xcconfig`

Override local opcional (gitignored):

```bash
cp Config/AISecrets.xcconfig.example Config/AISecrets.xcconfig
```

Configuración recomendada:
- Completar `SECURE_SERVER_BASE_URL`, `SECURE_SERVER_CLIENT_ID`, `SECURE_SERVER_CLIENT_SECRET`, `SECURE_SERVER_REQUIRE_TLS`
- Recibir `api_endpoint`, `model`, `api_key` desde backend

Fallback local:
- Completar `AI_API_ENDPOINT`, `AI_MODEL`, `AI_API_KEY`

### 3) Build y ejecución

```bash
./scripts/dev.sh "iPhone 16"
```

## Comandos de desarrollo

```bash
# build
./scripts/build.sh debug
./scripts/build.sh release
./scripts/build.sh clean

# ejecutar en simulador + logs
./scripts/run.sh "iPhone 16"

# flujo completo
./scripts/dev.sh "iPhone 16"

# conservar datos de la app en simulador
./scripts/dev_preserve_data.sh "iPhone 16"

# tests
xcodebuild test -project "Isla Reader.xcodeproj" -scheme "LanRead" -destination 'platform=iOS Simulator,name=iPhone 16'

# verificaciones
./scripts/test-localization.sh
./scripts/test-epub-parser.sh
./scripts/test-scripts.sh

# preflight App Review
./scripts/preflight-app-review.sh
./scripts/preflight-app-review.sh --full
```

## Backend opcional (arranque rápido)

```bash
cd server
python -m venv .venv
source .venv/bin/activate
pip install -e .
cp .env.example .env
uvicorn app.main:app --host 0.0.0.0 --port 8443 --no-access-log --ssl-keyfile certs/server.key --ssl-certfile certs/server.crt
```

Consulta detalles en [server/README.md](server/README.md).

## Privacidad

- Los datos de lectura se guardan localmente por defecto (Core Data + EPUB locales).
- Las funciones de IA y sincronización Notion requieren red.
- No se necesita cuenta para las funciones locales de lectura.
- Exportar/importar/resetear datos desde Ajustes.

## Documentación relacionada

- Requisitos: [Isla Reader/docs/requirements.md](Isla%20Reader/docs/requirements.md)
- Diseño de interacción de lectura: [Isla Reader/docs/reading_interaction_design.md](Isla%20Reader/docs/reading_interaction_design.md)
- Estrategia de prompts: [Isla Reader/docs/prompt_strategy.md](Isla%20Reader/docs/prompt_strategy.md)
- Setup de Notion OAuth: [Isla Reader/docs/NOTION_OAUTH_SETUP.md](Isla%20Reader/docs/NOTION_OAUTH_SETUP.md)
- Guía de scripts: [scripts/README.md](scripts/README.md)

## Licencia

MIT. Ver [LICENSE](LICENSE).
