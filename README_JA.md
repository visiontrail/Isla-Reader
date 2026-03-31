# LanRead - iOS向け AI EPUB リーダー

[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20iPadOS-lightgrey.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

LanRead は SwiftUI ベースの EPUB リーディングアプリです。AI による理解支援と、ローカル優先のデータ管理を重視しています。

## README 言語

- English: [README.md](README.md)
- 中文: [README_CN.md](README_CN.md)
- 日本語: [README_JA.md](README_JA.md)
- 한국어: [README_KO.md](README_KO.md)
- Español: [README_ES.md](README_ES.md)
- Deutsch: [README_DE.md](README_DE.md)
- Français: [README_FR.md](README_FR.md)

## 現在の状態（実装準拠）

- 対応プラットフォーム: iOS/iPadOS 16.0+
- Xcode プロジェクトの Marketing Version: `1.0.5`
- インポート対応形式: `EPUB`（Files アプリ経由）
- アプリ内 UI 言語: 英語、簡体字中国語、日本語、韓国語
- スクリプトのデフォルトシミュレータ（引数なし）: `iPhone 15 Pro`

## 最近の進捗（2026-03 スナップショット）

- Reader の安定性を改善（テキスト選択、ページ端の操作、横方向ドリフト抑制）。
- ハイライト導線を強化（複数選択マージ、ノート編集挙動の改善、巨大シェア画像のエクスポートフォールバック）。
- AI 操作を改善（Ask AI 入力の複数行自動リサイズ、翻訳/解説/質問アクションの並びと体験を統一）。
- メトリクスを改善（7日/週/月ウィンドウをローカルタイム境界に整列、summary と skimming のカウンタ分離）。
- Skimming フローを調整（章遷移後にインタースティシャルを表示、準備状態の通知を明確化）。

## 検証スナップショット（2026-03-31）

- `Isla ReaderTests`: 17 ファイル、`@Test` 59 件。
- `Isla ReaderUITests`: UI スモークテスト 2 ファイル。
- `server/tests`: バックエンド pytest 5 ファイル。

## 実装済み機能

### 読書とライブラリ
- EPUB インポート（SHA-256 による重複検出）
- ライブラリ検索、お気に入り、読書ステータス絞り込み
- 書籍詳細（メタデータ、ファイル情報、進捗）
- ハイライトの複数選択マージと画像カード共有
- リーダー機能:
  - 目次
  - タップ/スワイプでページ送り
  - 章ごとのページ状態管理
  - テーマ/文字組み設定
  - しおり追加・削除、しおり一覧
  - ハイライトとノート
  - ハイライト位置へのジャンプ

### AI 機能
- 読み始め時の AI サマリー（Core Data キャッシュ）
- ストリーミング風サマリー表示
- 選択テキスト/ハイライトへの AI 操作:
  - 翻訳
  - 解説
  - 質問
- AI 出力をノートへ挿入
- スキミングモード:
  - 章単位 AI 要約
  - 構造ポイント、重要文、キーワード、確認質問
  - スキミングから本文の該当位置へ遷移

### 進捗、通知、Live Activity
- 進捗ダッシュボード（週/月/年）
- 読書時間と目標達成率
- 毎日の読書リマインダー通知
- 当日読書進捗の Live Activity 更新（iOS 16.1+）

### 同期とデータ管理
- Notion OAuth 連携
- Notion ライブラリ初期化（親ページ選択・DB作成）
- ハイライト/ノート変更のキュー同期（リトライ/バックオフ）
- 読書データのエクスポート/インポート（JSON、書籍ファイル除く）
- キャッシュ使用量表示とキャッシュ削除
- ローカルデータ全削除（Core Data + EPUB ファイル + AI キャッシュ）

### セキュリティ/運用
- バックエンド経由の安全な AI 設定配布（`/v1/keys/ai`、HMAC 署名）
- `xcconfig` によるローカルフォールバック設定
- 更新ポリシー取得（`/v1/app/update-policy`）
- 任意のメトリクス送信（`/v1/metrics`）

### 広告（任意設定）
- Google Mobile Ads 統合
- サマリー画面/リーダー内シートのバナー枠
- スキミング中のリワード型インタースティシャル準備
- 広告ユニット ID 未設定やテスト ID の場合は自動でリクエストをスキップ

## 技術スタック

### iOS アプリ
- SwiftUI + Core Data
- Swift 5.9+
- ActivityKit（Live Activity）
- UserNotifications
- GoogleMobileAds SDK

### バックエンド（`server/`）
- FastAPI（Python 3.11+）
- HTTPS + HMAC 署名
- AI Key 配布、Notion OAuth finalize、メトリクス、更新ポリシー API

## プロジェクト構成

```text
.
├── Isla Reader/                       # iOS アプリ本体
│   ├── Views/
│   ├── Models/
│   ├── Utils/
│   ├── Assets.xcassets/
│   ├── *.lproj/                       # en/zh-Hans/ja/ko
│   └── Isla_Reader.xcdatamodeld/
├── Isla ReaderTests/                  # 単体テスト（Swift Testing）
├── Isla ReaderUITests/                # UI テスト（XCTest）
├── scripts/                           # 開発/ビルド/テストスクリプト
├── server/                            # 任意の安全バックエンド
├── README.md
└── README_CN.md
```

## クイックスタート

### 前提条件
- Xcode 15+
- iOS Simulator（推奨: `iPhone 16`。デバイス指定を省略した場合は `iPhone 15 Pro` が既定）
- macOS Command Line Tools
- バックエンド利用時: Python 3.11+

### 1) クローンして開く

```bash
git clone <your-repo-url>
cd LanRead-ios
open "Isla Reader.xcodeproj"
```

### 2) シークレット設定

基本設定はコミット済み:
- `Config/Base.xcconfig`

ローカル上書き（gitignore）:

```bash
cp Config/AISecrets.xcconfig.example Config/AISecrets.xcconfig
```

推奨構成:
- `SECURE_SERVER_BASE_URL` / `SECURE_SERVER_CLIENT_ID` / `SECURE_SERVER_CLIENT_SECRET` / `SECURE_SERVER_REQUIRE_TLS` を設定
- `api_endpoint` / `model` / `api_key` はバックエンドから配布

ローカルフォールバック:
- `AI_API_ENDPOINT` / `AI_MODEL` / `AI_API_KEY` を設定

### 3) ビルドと実行

```bash
./scripts/dev.sh "iPhone 16"
```

## 開発コマンド

```bash
# build
./scripts/build.sh debug
./scripts/build.sh release
./scripts/build.sh clean

# run + logs
./scripts/run.sh "iPhone 16"

# one-step dev
./scripts/dev.sh "iPhone 16"

# keep simulator app data
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

## 任意バックエンドの起動（最小）

```bash
cd server
python -m venv .venv
source .venv/bin/activate
pip install -e .
cp .env.example .env
uvicorn app.main:app --host 0.0.0.0 --port 8443 --no-access-log --ssl-keyfile certs/server.key --ssl-certfile certs/server.crt
```

詳細は [server/README.md](server/README.md) を参照してください。

## プライバシー

- 読書データは基本的に端末ローカル保存（Core Data + EPUB ファイル）。
- AI / Notion 同期にはネットワークが必要。
- ローカル読書機能にアカウントは不要。
- 設定画面でエクスポート/インポート/リセット可能。

## 関連ドキュメント

- 要件: [Isla Reader/docs/requirements.md](Isla%20Reader/docs/requirements.md)
- 読書 UX: [Isla Reader/docs/reading_interaction_design.md](Isla%20Reader/docs/reading_interaction_design.md)
- Prompt 戦略: [Isla Reader/docs/prompt_strategy.md](Isla%20Reader/docs/prompt_strategy.md)
- Notion OAuth 設定: [Isla Reader/docs/NOTION_OAUTH_SETUP.md](Isla%20Reader/docs/NOTION_OAUTH_SETUP.md)
- スクリプトガイド: [scripts/README.md](scripts/README.md)

## ライセンス

MIT。詳細は [LICENSE](LICENSE)。
