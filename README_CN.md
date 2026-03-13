# LanRead - 面向 iOS 的 AI EPUB 阅读器

[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20iPadOS-lightgrey.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

LanRead 是一款基于 SwiftUI 的阅读应用，聚焦 EPUB 阅读、AI 辅助理解与本地优先的数据体验。

## README 语言版本

- English: [README.md](README.md)
- 中文: [README_CN.md](README_CN.md)
- 日本語: [README_JA.md](README_JA.md)
- 한국어: [README_KO.md](README_KO.md)
- Español: [README_ES.md](README_ES.md)
- Deutsch: [README_DE.md](README_DE.md)
- Français: [README_FR.md](README_FR.md)

## 当前状态（与代码实现一致）

- App 目标平台：iOS/iPadOS 16.0+
- Xcode 工程当前 Marketing Version：`1.0`
- 主要导入格式：通过“文件”App 导入 `EPUB`
- App 内置 UI 语言：英文、简体中文、日文、韩文

## 已实现功能

### 阅读与书库
- EPUB 导入（基于 SHA-256 校验和的重复导入检测）
- 书库搜索、收藏、阅读状态筛选（想读/在读/暂停/已读）
- 书籍详情面板（元数据、文件信息、阅读进度）
- 阅读器能力：
  - 目录导航
  - 点按/滑动翻页
  - 分章节分页状态
  - 阅读主题与排版设置
  - 书签增删与书签列表
  - 文本高亮与笔记
  - 从高亮列表跳转回原文位置

### AI 功能
- AI 开始阅读导读摘要（缓存到 Core Data）
- 摘要流式风格显示
- 对选中文本/高亮执行 AI 动作：
  - 翻译
  - 解释
- AI 结果可直接插入高亮笔记
- 略读模式：
  - 按章节生成 AI 略读摘要
  - 结构要点、关键句、关键词、思考问题
  - 从略读章节一键进入全文阅读对应位置

### 进度、提醒与 Live Activity
- 阅读进度页（周/月/年维度）
- 阅读时长与目标完成率统计
- 每日阅读提醒通知
- Live Activity 实时更新当天阅读进度（iOS 16.1+）

### 同步与数据管理
- Notion OAuth 连接流程
- Notion 书库初始化（选择父页面并创建数据库）
- 高亮/笔记变更的队列化同步（含重试与退避）
- 阅读数据导出/导入（JSON，不包含书籍文件）
- 缓存空间统计与缓存清理
- 本地数据一键清除（Core Data + 已导入书籍文件 + 摘要缓存）

### 安全与运维能力
- 通过后端安全下发 AI 配置（`/v1/keys/ai`，HMAC 签名）
- 本地 `xcconfig` 兜底 AI 配置
- 版本更新策略拉取（`/v1/app/update-policy`）
- 可选指标上报（`/v1/metrics`）

### 广告（可选配置）
- 集成 Google Mobile Ads
- 摘要页/阅读器弹层中的 Banner 广告位
- 略读流程中的激励插屏预加载
- 未配置广告位或使用占位/测试广告位时会自动跳过请求

## 技术栈

### iOS 客户端
- SwiftUI + Core Data
- Swift 5.9+
- ActivityKit（Live Activity）
- UserNotifications
- GoogleMobileAds SDK

### 后端（`server/`）
- FastAPI（Python 3.11+）
- HTTPS + HMAC 请求签名
- 提供 AI Key 下发、Notion OAuth finalize、指标上报、更新策略等接口

## 项目结构

```text
.
├── Isla Reader/                       # iOS 应用源码
│   ├── Views/                         # SwiftUI 页面
│   ├── Models/                        # Core Data 实体/扩展
│   ├── Utils/                         # AI、Notion、提醒、缓存等服务
│   ├── Assets.xcassets/
│   ├── *.lproj/                       # 应用内多语言（en/zh-Hans/ja/ko）
│   └── Isla_Reader.xcdatamodeld/
├── Isla ReaderTests/                  # 单元测试（Swift Testing）
├── Isla ReaderUITests/                # UI 冒烟测试（XCTest）
├── scripts/                           # 本地开发/构建/测试脚本
├── server/                            # 可选安全后端
├── README.md
└── README_CN.md
```

## 快速开始

### 环境要求
- Xcode 15+
- iOS 模拟器运行时（推荐设备：`iPhone 16`）
- macOS 命令行工具
- 后端可选：Python 3.11+

### 1）克隆并打开工程

```bash
git clone <your-repo-url>
cd LanRead-ios
open "Isla Reader.xcodeproj"
```

### 2）配置应用密钥

默认基础配置已提交：
- `Config/Base.xcconfig`

可选本地覆盖（已 gitignore）：

```bash
cp Config/AISecrets.xcconfig.example Config/AISecrets.xcconfig
```

推荐生产式配置：
- 填写安全服务配置（`SECURE_SERVER_BASE_URL`、`SECURE_SERVER_CLIENT_ID`、`SECURE_SERVER_CLIENT_SECRET`、`SECURE_SERVER_REQUIRE_TLS`）
- 由后端下发 `api_endpoint`、`model`、`api_key`
- 填写 AdMob 广告位（`ADMOB_BANNER_AD_UNIT_ID`、`ADMOB_INTERSTITIAL_AD_UNIT_ID`、`ADMOB_REWARDED_INTERSTITIAL_AD_UNIT_ID`）
- 在奖励插屏广告位尚未通过实体机归档包验证前，保持 `ADMOB_ENABLE_REWARDED_INTERSTITIAL_FALLBACK = NO`

本地兜底配置：
- 填写 `AI_API_ENDPOINT`、`AI_MODEL`、`AI_API_KEY`

### 3）构建并运行

```bash
./scripts/dev.sh "iPhone 16"
```

## 开发命令

```bash
# 仅构建
./scripts/build.sh debug
./scripts/build.sh release
./scripts/build.sh clean

# 在模拟器运行已构建 app + 实时日志
./scripts/run.sh "iPhone 16"

# 一键构建 + 运行
./scripts/dev.sh "iPhone 16"

# 保留模拟器已安装应用数据
./scripts/dev_preserve_data.sh "iPhone 16"

# 单元 + UI 测试
xcodebuild test -project "Isla Reader.xcodeproj" -scheme "LanRead" -destination 'platform=iOS Simulator,name=iPhone 16'

# 辅助检查
./scripts/test-localization.sh
./scripts/test-epub-parser.sh
./scripts/test-scripts.sh

# 提审前预检
./scripts/preflight-app-review.sh
./scripts/preflight-app-review.sh --full
```

## 可选后端快速启动

```bash
cd server
python -m venv .venv
source .venv/bin/activate
pip install -e .
cp .env.example .env
uvicorn app.main:app --host 0.0.0.0 --port 8443 --no-access-log --ssl-keyfile certs/server.key --ssl-certfile certs/server.crt
```

完整部署与安全说明见：[server/README.md](server/README.md)

## 隐私说明

- 核心阅读数据默认保存在本地设备（Core Data + 本地 EPUB 文件）。
- AI 与 Notion 同步功能需要网络。
- 本地阅读核心能力不需要账号。
- 可在设置中执行导出、导入与重置。

## 相关文档

- iOS 需求文档：[Isla Reader/docs/requirements.md](Isla%20Reader/docs/requirements.md)
- 阅读交互设计：[Isla Reader/docs/reading_interaction_design.md](Isla%20Reader/docs/reading_interaction_design.md)
- Prompt 策略：[Isla Reader/docs/prompt_strategy.md](Isla%20Reader/docs/prompt_strategy.md)
- Notion OAuth 配置：[Isla Reader/docs/NOTION_OAUTH_SETUP.md](Isla%20Reader/docs/NOTION_OAUTH_SETUP.md)
- 脚本说明：[scripts/README.md](scripts/README.md)

## 许可证

MIT，详见 [LICENSE](LICENSE)。
