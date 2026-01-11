# IslaBooks - AI 驱动的阅读助手

[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20iPadOS-lightgrey.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.1.2-green.svg)](CHANGELOG.md)

> 让每本书成为可对话的导师：获取、阅读、理解与讨论，尽在一处。

## 概览

IslaBooks 是一款面向 iOS 与 iPadOS 的智能电子书阅读应用，利用 AI 技术提升阅读体验。它聚焦数字阅读中的常见痛点：难以获取、理解门槛高、阅读不完整、记忆留存差、缺少讨论伙伴。

### 关键特性

- 📚 本地图书导入：支持从本地存储或“文件”App 导入 ePub 与纯文本
- 🤖 AI 导读摘要：打开即生成章节与全书摘要
- 🧭 略读模式：章节骨架摘要与快速导航
- 💬 交互式阅读助手：可针对选区、章节或整书进行提问
- 🎯 理解诊断：自动生成测验评估理解程度
- 🔖 高级阅读器：书签、高亮、批注、搜索与可定制主题
- ☁️ iCloud 同步：通过 CloudKit 在设备间无缝同步
- 🔗 同步到 Notion：将书签与标注同步到 Notion
- 🌙 阅读模式：夜间模式、可调字体、行距与版式
- 🔒 隐私优先：无需注册，本地优先，可选云同步

## 愿景

让每本书成为可对话的导师。

IslaBooks 将传统电子阅读与 AI 理解工具结合，使读者不仅能高效获取内容，更能主动参与与深度理解复杂材料。

## 目标用户

### 学习型读者
- 需要高效获取知识的学生与职场人士
- 希望理解并总结复杂材料的个体
- 受益于交互式学习与理解评估的读者

### 轻阅读用户
- 期望获取个性化图书推荐的用户
- 喜欢在深入阅读前快速了解要点的读者
- 重视舒适、无干扰阅读体验的用户

## 核心能力

### 1. 图书管理
- 从“文件”App、iCloud Drive 或本地存储导入书籍
- 支持 ePub 与纯文本格式
- 使用自定义标签与分类组织图书
- 跟踪阅读进度与数据统计
- 在书库中搜索与筛选

### 2. AI 加持阅读

#### 即时摘要
- 全书概览，涵盖关键要点与章节结构
- 章节摘要，突出核心概念
- 自动缓存，可离线访问
- 支持手动刷新

#### 交互式问答
- 选区提问：高亮文本后进行翻译、解释或扩展
- 章节级提问：围绕主题、概念或论点提问
- 整书级讨论：跨章节交叉引用观点
- 引用支持：回答包含对应原文出处

### 3. 理解工具

#### 理解诊断
- 打开新书时自动生成 2–5 道测验题
- 即时反馈与详细解析
- 基于结果给出学习路径建议

#### 知识卡片
- 一键将高亮与笔记转为闪卡
- AI 生成术语表条目与示例
- 支持导出为 Markdown/CSV 用于复习

### 4. 阅读体验

#### 核心阅读功能
- 目录导航
- 全文搜索
- 书签与进度跟踪
- 多色高亮
- 行内批注
- 阅读统计

#### 个性化设置
- 多套主题（亮色、暗色、仿古、自定义）
- 可调字体大小与字族
- 可配置行距与页边距
- 夜间模式与蓝光降低

### 5. 同步与隐私

#### iCloud 集成
- 通过 CloudKit 自动同步（无需应用内注册）
- 同步内容：阅读进度、书签、高亮、笔记、设置
- 可选禁用云同步，仅本地存储
- 一键删除云端数据

#### 隐私承诺
- 最小化数据采集
- 不接入第三方分析或追踪
- 用户拥有导入内容的完全所有权
- AI 请求匿名化处理
- 支持完整数据导出

## 技术架构

### 客户端
- 平台：iOS 16.0+，iPadOS 16.0+
- 语言：Swift 5.9+
- UI 框架：SwiftUI
- 存储：Core Data + iCloud CloudKit

### AI 集成
- 模型：兼容 OpenAI API（可配置）
- 流式：渐进式 UI 更新（模拟流式）；计划支持 SSE
- 上下文管理：基于规则的段落抽取（无向量数据库）
- 缓存：积极的摘要与响应缓存

### 数据同步
- 服务：CloudKit 私有数据库
- 范围：用户书库、进度、批注、偏好设置
- 冲突解决：时间戳末写胜（Last-write-wins）
- 离线支持：完整离线阅读，重联后同步

## 安装

### 环境要求
- iOS 16.0+ 或 iPadOS 16.0+
- Xcode 15.0+
- Swift 5.9+
- 有效 Apple 开发者账号（用于 CloudKit）

### 设置步骤

1. 克隆仓库
```bash
git clone https://github.com/yourusername/IslaBooks-ios.git
cd IslaBooks-ios/Isla\ Reader
```

2. 使用 Xcode 打开
```bash
open Isla\ Reader.xcodeproj
```

3. 配置 CloudKit
   - 在项目设置启用 iCloud 能力
   - 选择 CloudKit 容器
   - 在 Signing & Capabilities 中开启 “CloudKit”

4. 配置 AI 与安全服务器
   - 将 `Config/AISecrets.xcconfig.example` 复制为 `Config/AISecrets.xcconfig`
   - 设置 `AI_API_ENDPOINT` 与 `AI_MODEL`
   - 二选一：
     - 本地直连：设置 `AI_API_KEY`
     - 安全服务器：留空 `AI_API_KEY`，并设置 `SECURE_SERVER_BASE_URL`、`SECURE_SERVER_CLIENT_ID`、`SECURE_SERVER_CLIENT_SECRET`、`SECURE_SERVER_REQUIRE_TLS`

5. 构建与运行
   - 选择目标设备或模拟器
   - 按 `Cmd + R` 构建并运行

### 安全密钥交换服务器

- 后端位于 `server/`（FastAPI + HMAC + HTTPS），详细见 `server/README.md`
- 快速启动：`cd server && python -m venv .venv && source .venv/bin/activate && pip install -e .`
- 复制 `.env.example` 为 `.env`，设置 `ISLA_API_KEY`、`ISLA_CLIENT_ID`、`ISLA_CLIENT_SECRET`，然后运行：
  `uvicorn app.main:app --host 0.0.0.0 --port 8443 --ssl-keyfile certs/server.key --ssl-certfile certs/server.crt`

## 使用

### 快速开始

1. 导入你的第一本书
   - 在书架点击 “＋”
   - 从“文件”App 选择 ePub 或 .txt 文件
   - 书籍将出现在你的书库

2. 使用 AI 辅助阅读
   - 点击书籍打开阅读器
   - 首屏显示 AI 生成的导读摘要
   - 选中任意文本即可提问、翻译或获取解释

3. 略读模式
   - 长按点击 “略读” 按钮，显示章节摘要
   - 左右滑动或点击目录跳转至对应章节

4. 跟踪进度
   - 自动保存书签
   - 通过 iCloud 在设备间同步进度
   - 在“我的书库”查看阅读统计

### 高级功能

#### 自定义 AI 操作
为选区预设动作：
- 翻译为【目标语言】
- 解释该概念
- 提供示例
- 与【概念】进行对比
- 用简明语言总结

#### 导出与备份
- 将高亮与笔记导出为 Markdown
- 将知识卡片导出为 CSV
- 将书库备份到“文件”App

## 路线图

### v0.1 MVP（当前）
- [x] 本地文件导入（ePub、纯文本）
- [x] 基础 ePub 渲染引擎
- [x] 阅读器基础能力（目录、书签、进度、主题）
- [x] AI 书籍摘要与缓存
- [x] 略读模式（章节摘要与跳转）


### v0.2（MVP发布）
- [ ] 性能优化
- [ ] 稳定性提升
- [ ] 合规与成本治理
- [ ] App Store 提交

### v0.5（计划）
- [ ] 选区问答（翻译、解释、总结）
- [ ] 最小 iCloud 同步（仅进度）

### v1.0（未来）




## 开发

### 项目结构

```
Isla Reader/
├── Isla Reader/
│   ├── Isla_ReaderApp.swift       # 应用入口
│   ├── ContentView.swift          # 主视图
│   ├── Models/                    # 数据模型
│   ├── Views/                     # SwiftUI 视图
│   ├── Utils/                     # 工具与服务
│   ├── Persistence.swift          # Core Data 栈
│   ├── Isla_Reader.xcdatamodeld/  # Core Data 模型
│   ├── en.lproj/                  # 英文本地化
│   ├── zh-Hans.lproj/             # 简体中文本地化
│   ├── ja.lproj/                  # 日文本地化
│   ├── ko.lproj/                  # 韩文本地化
│   ├── Info.plist                 # 应用配置
│   ├── Isla_Reader.entitlements   # 应用权限配置
│   ├── docs/                      # 应用文档
│   └── Assets.xcassets/           # 图片与配色
├── Isla Reader.xcodeproj/         # Xcode 工程
├── Isla ReaderTests/              # 单元测试
├── Isla ReaderUITests/            # UI 测试
├── scripts/                       # 构建与自动化脚本
└── server/                        # 安全密钥交换服务（FastAPI）
```

### 开发构建

```bash
# 运行全部测试
xcodebuild test -project "Isla Reader.xcodeproj" -scheme "LanRead" -destination 'platform=iOS Simulator,name=iPhone 16'

# 构建模拟器版本
xcodebuild build -project "Isla Reader.xcodeproj" -scheme "LanRead" -destination 'platform=iOS Simulator,name=iPhone 16'

# 构建设备版本
xcodebuild build -project "Isla Reader.xcodeproj" -scheme "LanRead" -destination 'generic/platform=iOS'
```

### 测试

```bash
# 运行单元测试
cd scripts
./test-scripts.sh

# 在模拟器中运行
./simulator.sh
```

## 合规与隐私

### App Store 指南
- 5.1 隐私：最小化数据收集，提供隐私政策，可删除数据
- 5.1.1 权限：权限请求提供明确用途说明
- 5.1.3 账户删除：应用内删除账号并同时删除服务端数据
- 3.1 支付：数字内容/功能（如适用）需使用 IAP
- 4.2 质量：功能完整，无崩溃，达标可发布

### 隐私特性
- 不收集邮箱或个人身份信息
- iCloud 仅用于数据同步（可选）
- AI 请求匿名化且不记录
- 用户完全掌控数据，可导出/删除
- 符合 App 隐私营养标签要求

### 版权与内容
- 用户对导入内容的合法性负责
- 应用不提供书籍下载或聚合服务
- 示例书籍应来自古登堡计划等公共领域
- 所有 AI 生成内容均包含引用与来源标注

## 贡献

我们欢迎所有贡献！提交 PR 前请阅读 [贡献指南](CONTRIBUTING.md)。

### 开发流程
1. Fork 仓库
2. 创建功能分支（`git checkout -b feature/amazing-feature`）
3. 提交变更（`git commit -m 'Add amazing feature'`）
4. 推送分支（`git push origin feature/amazing-feature`）
5. 创建 Pull Request

### 代码风格
- 遵循 Swift API 设计指南
- 使用 SwiftLint 保持代码一致性
- 为新功能编写测试
- 按需更新文档

## 支持

### 文档
- [快速上手](scripts/QUICK_START.md)
- [需求规格说明](Isla%20Reader/docs/requirements.md)
- [阅读交互设计](Isla%20Reader/docs/reading_interaction_design.md)
- [提示策略](Isla%20Reader/docs/prompt_strategy.md)

## 许可证

项目在 MIT 许可证下发布——详见 [LICENSE](LICENSE)。

## 致谢

- 灵感来源：用 AI 让知识更易获得
- 构建于 SwiftUI 与 Core Data
- 通过兼容 OpenAI 的 API 集成 AI
- 特别感谢开源社区

## 更新日志

更新日志将发布在 Releases；当前进展请参见上方路线图。

---

**当前版本**：v1.0 
**最近更新**：2025-12-12  
**状态**：积极开发（MVP 阶段）

为热爱学习的读者倾心打造。
