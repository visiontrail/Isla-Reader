# LanRead Batch Automation Feature Spec

## 文档信息
- 版本: v0.1.0
- 日期: 2026-04-07
- 状态: Draft
- 负责人: Codex + 项目维护者
- 目标分支: 当前独立分支
- 相关范围: 新增独立 Swift Package，不修改现有 iOS App 运行路径

## 文档目的
本文件用于定义 LanRead 的 macOS 批处理自动化能力，并作为后续逐步实现时的单一执行文档。

它同时承担四个作用：

1. 说明要做什么。
2. 约束第一阶段不做什么。
3. 定义分阶段实现顺序和验收标准。
4. 记录实现过程中的决策、进度、验证结果和遗留问题。

## 变更记录
| 日期 | 版本 | 更改 | 作者 |
| --- | --- | --- | --- |
| 2026-04-07 | v0.1.0 | 创建 Batch Automation Feature Spec 初稿 | Codex |

---

## 一句话定义
将整本 EPUB 交给独立的 macOS CLI 流水线，自动抽取适合传播的高亮与评论，并批量输出分享图片与结构化清单，为后续 caption 生成和社交媒体自动发布打基础。

## 背景
当前 iOS App 已具备以下基础能力：

- EPUB 解析
- 高亮/笔记分享卡片导出
- AI 调用与相关 prompt 能力

但这些能力主要服务于前台交互式使用，不适合 headless 自动化。尤其是以下问题会阻碍批处理落地：

- iOS App 的 AI 配置依赖前台应用上下文，不适合 CLI。
- 分享图片渲染基于 UIKit，不适合直接用于 macOS 批量生成。
- 当前高亮与笔记来源依赖用户交互，而不是“整本书自动抽取”。
- 后续接社交媒体发布时，需要稳定、可脚本化、可重跑的产物目录与 manifest。

因此，本功能应作为仓库内独立的 Swift Package 落地，而不是继续塞进现有 App target。

## 产品目标

### MVP 目标
- 支持单本 EPUB 输入。
- 自动生成 10 到 20 条适合分享的高亮候选。
- 为每条候选生成分享图 PNG。
- 输出 `manifest.json`、中间结果和日志。
- 支持失败后重跑，不依赖 iOS App UI。

### 后续扩展目标
- 支持目录批量处理多本书。
- 支持生成 captions。
- 支持接入社交媒体发布流水线。
- 支持自动化调度和重试策略。

## 非目标
以下内容不属于 MVP：

- 不修改现有 iOS App 的阅读流程。
- 不写回高亮/笔记到 App 的 Core Data。
- 不做 macOS GUI。
- 不在第一阶段接入社交媒体 API。
- 不做“整本一次性发给 AI”的大上下文方案。
- 不做复杂的来源 offset 回写。

---

## 设计原则

### 1. 独立运行
批处理功能必须可以在 macOS 上通过 `swift run` 独立执行，不依赖前台应用状态。

### 2. 尽量复用现有逻辑
优先复用现有 EPUB 解析、分享 payload 设计、文案结构和已有测试经验，避免平行重写。

### 3. 产物可追溯
每一张输出图都必须能追溯回书籍、章节、文本块和 AI 选择过程。

### 4. 重跑稳定
同一本书重复执行时，输入、配置和版本不变的情况下，输出结构和中间记录应尽量稳定。

### 5. 先产物，后平台
先把“生成候选 + 输出图片 + 产出 manifest”做扎实，再考虑 caption 和自动发布。

---

## 现有代码复用锚点

### 可复用
- `Isla Reader/Utils/EPubParser.swift`
- `Isla Reader/Utils/HighlightShareCardRenderer.swift`
- `Isla Reader/Utils/AIConfig.swift`
- `Isla Reader/Utils/AISummaryService.swift`
- `Isla Reader/Utils/ReadingAIService.swift`

### 复用策略
- `EPubParser.swift`: 优先抽取或桥接 EPUB 解析结果，不改动当前 App 行为。
- `HighlightShareCardPayload`: 复用字段设计、文案组织和版式参数。
- AI 调用: 参考现有请求结构和 prompt 组织方式，但 CLI 不复用 `AIConfig.current()` 的运行机制。
- 日志: CLI 新增自己的日志模块，不直接依赖 App UI 相关逻辑。

### 不直接复用
- `HighlightShareCardRenderer` 的 UIKit/macOS 不兼容部分
- 依赖用户 consent、`UserDefaults`、`Bundle.main` 或前台 UI 生命周期的配置读取逻辑

---

## 目标目录结构
```text
Package.swift
Batch/
  BatchCLI/
  BatchCore/
  BatchAI/
  BatchRender/
  BatchModels/
  BatchSupport/
scripts/
  batch-generate.sh
```

## 模块职责

### `BatchCLI`
- 命令入口
- 参数解析
- 运行模式选择
- 调用核心 pipeline

### `BatchCore`
- 书籍处理流水线
- 文本切块
- 候选聚合、去重、筛选
- 执行状态编排

### `BatchAI`
- provider 配置加载
- prompt 组织
- stage 1 抽取调用
- stage 2 筛选调用
- 响应解析与错误包装

### `BatchRender`
- macOS 下的分享图渲染
- share payload 到 PNG 的批量输出

### `BatchModels`
- 中间数据结构
- manifest schema
- AI 输入输出对象

### `BatchSupport`
- 日志
- 文件输出
- checksum/hash
- 运行配置
- 时间戳、slug、目录组织

---

## CLI 设计

### MVP 命令
```bash
swift run lanread-batch generate \
  --epub "/path/book.epub" \
  --output "/path/out" \
  --highlights 20 \
  --language zh-Hans \
  --style white \
  --provider-config "/path/ai.json"
```

### 后续预留命令
```bash
swift run lanread-batch generate --input-dir "/books" --output "/out"
swift run lanread-batch review --manifest "/out/book/manifest.json"
swift run lanread-batch captions --manifest "/out/book/manifest.json"
swift run lanread-batch publish --manifest "/out/book/manifest.json" --channel xiaohongshu
```

### CLI 参数优先级
`命令行参数 > 配置文件 > 环境变量 > 默认值`

### 环境变量建议
- `LANREAD_AI_ENDPOINT`
- `LANREAD_AI_KEY`
- `LANREAD_AI_MODEL`

---

## 输入输出契约

### 输入
- `epub`: 单本 EPUB 文件路径
- `output`: 输出目录
- `highlights`: 目标输出条数
- `language`: AI 输出语言
- `style`: 分享图样式，首版对应 `none` / `white` / `black`
- `provider-config`: AI provider 配置文件路径

### 输出目录
```text
out/
  book-slug/
    manifest.json
    excerpts.jsonl
    candidates.stage1.jsonl
    selected.stage2.json
    captions.jsonl
    prompts/
      stage1/
      stage2/
    images/
      001.png
      002.png
    logs/
      run.log
      metrics.json
```

### manifest.json 建议结构
```json
{
  "run_id": "uuid",
  "generated_at": "2026-04-07T12:00:00Z",
  "source_file": "/path/book.epub",
  "book": {
    "title": "string",
    "author": "string",
    "language": "string"
  },
  "config": {
    "highlights": 20,
    "language": "zh-Hans",
    "style": "white",
    "model": "gpt-x"
  },
  "stats": {
    "chapters": 0,
    "windows": 0,
    "stage1_candidates": 0,
    "final_items": 0
  },
  "items": []
}
```

### item 建议结构
```json
{
  "id": "item-001",
  "chapter_title": "string",
  "chapter_order": 3,
  "source_excerpt": "string",
  "highlight_text": "string",
  "note_text": "string",
  "image_path": "images/001.png",
  "score": 0.91,
  "tags": ["humanity", "memory"],
  "source_locator": {
    "chapter_order": 3,
    "excerpt_index": 12,
    "excerpt_hash": "sha256"
  }
}
```

### 追溯策略
MVP 先不记录精确 offset，使用以下三元组追溯来源：

- `chapter_order`
- `excerpt_index`
- `excerpt_hash`

---

## 核心流水线

### Step 1. EPUB 解析
- 读取书籍 metadata 和章节内容
- 标准化章节顺序
- 过滤封面、目录等非正文内容

### Step 2. 文本切块
- 按章节切分
- 清洗正文
- 组装稳定窗口
- 为每个窗口生成稳定 ID 和 hash

### Step 3. Stage 1 AI 抽取
- 输入单个窗口
- 输出 3 到 8 条候选高亮
- 要求高亮文本必须来自原文
- 允许 AI 生成简短 note / framing

### Step 4. 全书候选聚合
- 合并所有窗口候选
- 去重
- 基于长度、重复度、章节分散度和质量分做初筛

### Step 5. Stage 2 AI 全书筛选
- 从候选池里选出最终 10 到 30 条
- 兼顾主题分布和章节分布
- 控制长度与传播适配性

### Step 6. 分享卡渲染
- 将最终候选转换为分享图 payload
- 批量输出 PNG
- 记录失败项和成功项

### Step 7. 产物写盘
- 写出 `manifest.json`
- 写出中间 json/jsonl
- 写出日志和统计信息

---

## 文本切块策略

### 目标
兼顾语义完整性、窗口稳定性、AI 成本控制和来源追溯。

### 规则
- 先按章节切
- 再按段落聚合
- 中文窗口目标长度: 800 到 1800 字
- 英文窗口目标长度: 500 到 1200 词
- overlap: 15% 到 20%
- 每个窗口保留以下字段：
  - `chapterOrder`
  - `chapterTitle`
  - `windowIndex`
  - `text`
  - `textHash`

### 约束
- 不跨越章节边界
- 尽量不从句中间截断
- 清理多余空白、重复换行和显著噪音字符
- 对目录、版权页、致谢页等非正文做可配置过滤

---

## AI 设计

### 总体策略
采用两阶段 AI，而不是一步到位：

1. 局部抽取
2. 全书筛选

这样可以提升稳定性、降低上下文压力，并让失败重试更容易。

### Stage 1: 局部抽取

#### 输入
- 单个文本窗口
- 书籍元数据
- 章节元数据
- 输出语言

#### 输出
每个窗口返回 3 到 8 条候选，每条包含：

- `highlight_text`
- `note_text`
- `tags`
- `score`
- `reason`

#### 关键约束
- `highlight_text` 必须直接摘自原文
- 不允许改写高亮文本
- `note_text` 允许是 AI 生成的一句 framing/comment
- 候选必须适合做社交媒体分享图

### Stage 2: 全书筛选

#### 输入
- 全书候选列表
- 每条候选的章节、长度、分数、标签、hash

#### 输出
- 最终入选列表
- 排序结果
- 可选拒绝原因

#### 关键约束
- 避免重复或同义重复
- 章节尽量分散
- 避免句子过长
- 避免过碎、过学术、过空泛
- 优先保留“可传播、可理解、可配图”的句子

### 失败策略
- stage 1 允许单窗口失败并跳过，记录到日志
- stage 2 失败时允许退回本地排序规则生成保底结果

---

## 渲染设计

### 目标
在 macOS 环境下批量生成视觉上接近现有分享卡的 PNG，但不依赖 UIKit、Photos 或 ShareSheet。

### 方案
- 复用 `HighlightShareCardPayload` 的结构思想
- 新增 `BatchRender/ShareCardRenderer.swift`
- 使用 `SwiftUI + ImageRenderer`
- 在 macOS 下通过 `AppKit` / `NSImage` 输出最终图片

### MVP 范围
- 样式支持 `none` / `white` / `black`
- 支持有 note 和无 note 两种版式
- 支持书名、章节名、页脚文案
- 封面图为可选项

### 非目标
- 第一版不追求和 iOS 像素级一致
- 第一版不做复杂主题系统

---

## 配置与安全

### 配置来源
- 命令行参数
- `ai.json`
- 环境变量

### `ai.json` 示例
```json
{
  "endpoint": "https://example.com/v1/chat/completions",
  "apiKey": "YOUR_KEY",
  "model": "gpt-4.1-mini"
}
```

### 原则
- CLI 不读取 App 的前台 consent 状态
- CLI 不使用 `Bundle.main` 的 App 配置通道
- 不在仓库中提交真实 key
- 所有 provider 信息在日志中只打印脱敏值

---

## 记录功能设计
本 spec 本身就是记录容器。实现过程中统一在本文件更新以下几块内容。

### 1. 阶段状态板
用于标记当前做到哪一步。

| 阶段 | 名称 | 状态 | 负责人 | 开始日期 | 完成日期 | 备注 |
| --- | --- | --- | --- | --- | --- | --- |
| P0 | Package 骨架与 CLI 命令入口 | TODO |  |  |  |  |
| P1 | EPUB 接入与文本切块 | TODO |  |  |  |  |
| P2 | Stage 1 AI 抽取 | TODO |  |  |  |  |
| P3 | 候选聚合与 Stage 2 筛选 | TODO |  |  |  |  |
| P4 | macOS 分享图渲染 | TODO |  |  |  |  |
| P5 | manifest / 日志 / 重跑能力 | TODO |  |  |  |  |
| P6 | 目录批处理与脚本封装 | TODO |  |  |  |  |
| P7 | captions / publish 预留接口 | TODO |  |  |  |  |

状态建议值：
- `TODO`
- `IN_PROGRESS`
- `BLOCKED`
- `DONE`

### 2. 实现清单
- [ ] 新增 `Package.swift`
- [ ] 建立 `Batch/` 目录和 targets
- [ ] 跑通 `swift run lanread-batch --help`
- [ ] 接入单本 EPUB 解析
- [ ] 输出稳定窗口 `excerpts.jsonl`
- [ ] 跑通 Stage 1 AI 抽取
- [ ] 输出 `candidates.stage1.jsonl`
- [ ] 完成候选去重与初筛
- [ ] 跑通 Stage 2 AI 筛选
- [ ] 输出 `selected.stage2.json`
- [ ] 完成 macOS PNG 渲染
- [ ] 输出 `manifest.json`
- [ ] 增加失败重跑能力
- [ ] 增加 `scripts/batch-generate.sh`
- [ ] README 补充内部批处理说明

### 3. 决策日志
重大实现取舍记录在这里，避免后面反复讨论同一个问题。

| 日期 | 主题 | 决策 | 原因 | 影响 |
| --- | --- | --- | --- | --- |
| 2026-04-07 | 功能形态 | 采用独立 Swift CLI + Swift Package | 避免污染 iOS App 主路径，更适合自动化与脚本调用 | 后续可直接接 Skill、cron、发布流水线 |

### 4. 实施日志
每完成一步，在这里追加记录。

| 日期 | 阶段 | 动作 | 结果 | 后续 |
| --- | --- | --- | --- | --- |
|  |  |  |  |  |

### 5. 验证记录
每个阶段的实际验证命令和结果写在这里。

| 日期 | 阶段 | 验证命令 | 结果 | 备注 |
| --- | --- | --- | --- | --- |
|  |  |  |  |  |

### 6. 风险与阻塞记录
| 日期 | 类型 | 描述 | 当前处理 | 状态 |
| --- | --- | --- | --- | --- |
|  |  |  |  |  |

---

## 分阶段实施计划

## P0. Package 骨架与 CLI 命令入口

### 目标
在不影响现有 iOS target 的前提下，为 batch automation 建立最小可运行骨架。

### 交付物
- `Package.swift`
- `BatchCLI` 可执行 target
- `BatchCore` / `BatchAI` / `BatchRender` / `BatchModels` / `BatchSupport` 基础 target
- `generate` 命令空实现

### 任务
- 定义 package products 和 target 依赖关系
- 选定 CLI 参数解析方案
- 确定日志输出目录规则
- 定义统一错误类型

### 验收
- `swift build` 成功
- `swift run lanread-batch --help` 可执行
- `swift run lanread-batch generate --help` 可执行

## P1. EPUB 接入与文本切块

### 目标
输入一本 EPUB，输出稳定的窗口化正文中间结果。

### 交付物
- EPUB 元数据读取
- 章节遍历
- 文本清洗
- `excerpts.jsonl`

### 任务
- 接入或抽取 `EPubParser`
- 设计 `BookExcerpt` 模型
- 实现切块规则和 overlap
- 为每个 excerpt 计算 hash

### 验收
- 指定测试 EPUB 后成功输出 `excerpts.jsonl`
- excerpt 数量与章节顺序合理
- 相同输入可产生稳定 hash

## P2. Stage 1 AI 抽取

### 目标
让每个窗口输出结构化候选高亮。

### 交付物
- provider 配置加载
- stage 1 prompt
- AI client
- `candidates.stage1.jsonl`

### 任务
- 设计 stage 1 response schema
- 增加基础超时、重试和错误包装
- 记录原始 prompt 和响应摘要

### 验收
- 对单本书执行后，可得到候选列表
- 候选中的 `highlight_text` 都能在原文窗口中找到
- 单窗口失败不会导致整本任务崩溃

## P3. 候选聚合与 Stage 2 筛选

### 目标
从全书候选里选出最终一组高质量分享项。

### 交付物
- 本地去重规则
- 本地初筛规则
- stage 2 prompt
- `selected.stage2.json`

### 任务
- 定义去重 key
- 设计章节分散度策略
- 增加 stage 2 失败时的本地保底排序

### 验收
- 最终入选数量接近目标数量
- 重复内容显著下降
- 最终结果覆盖多个章节

## P4. macOS 分享图渲染

### 目标
将最终候选批量输出为 PNG。

### 交付物
- `ShareCardRenderer.swift`
- 图片文件输出
- 图片文件命名规则

### 任务
- 定义 macOS 版 payload 与样式参数
- 适配 `none` / `white` / `black`
- 处理超长文案的版式降级

### 验收
- 成功输出 `images/001.png` 等文件
- 图片可打开，文案排版可读
- 不依赖 iOS UIKit 环境

## P5. manifest / 日志 / 重跑能力

### 目标
让每次运行都形成可追溯、可恢复的产物包。

### 交付物
- `manifest.json`
- `run.log`
- `metrics.json`
- 重跑策略

### 任务
- 串起最终产物写盘
- 记录运行摘要和失败项
- 定义覆盖写入或增量写入策略

### 验收
- 输出目录结构完整
- 失败后可重跑，并跳过已完成环节或覆盖重建
- manifest 中的 `image_path`、`source_locator` 与实际文件一致

## P6. 目录批处理与脚本封装

### 目标
让工具能被外部脚本和自动化系统稳定调用。

### 交付物
- `--input-dir`
- `scripts/batch-generate.sh`
- 批量运行摘要输出

### 任务
- 目录扫描
- 每本书独立输出目录
- 失败书目汇总

### 验收
- 指定目录后可逐本生成
- 单本失败不会中断整个批次

## P7. captions / publish 预留接口

### 目标
为后续社交媒体发布打好数据接口，但不在 MVP 实现发布逻辑。

### 交付物
- `captions` 命令桩
- `publish` 命令桩
- manifest 中保留扩展字段

### 验收
- 命令接口稳定
- 不影响 generate 主路径

---

## 数据模型草案

### `BatchRunConfig`
- `epubPath`
- `outputPath`
- `targetHighlightCount`
- `language`
- `style`
- `providerConfigPath`
- `overwritePolicy`

### `BookExcerpt`
- `id`
- `chapterOrder`
- `chapterTitle`
- `windowIndex`
- `text`
- `textHash`
- `wordCount`

### `Stage1Candidate`
- `id`
- `excerptId`
- `highlightText`
- `noteText`
- `tags`
- `score`
- `reason`

### `SelectedHighlightItem`
- `id`
- `candidateId`
- `rank`
- `imagePath`
- `sourceLocator`

### `BatchManifest`
- `runId`
- `generatedAt`
- `sourceFile`
- `book`
- `config`
- `stats`
- `items`

---

## 错误处理策略
- 解析失败: 终止当前书籍，输出错误日志
- 单窗口 AI 失败: 记录错误并跳过该窗口
- stage 2 失败: 使用本地保底排序继续生成
- 单张图片渲染失败: 保留 manifest 条目并记录失败状态
- 文件写入失败: 终止当前运行并明确退出码

## 可观测性

### 日志最少要求
- 运行开始/结束时间
- 输入文件和配置摘要
- 章节数、窗口数、候选数、最终条数
- 每阶段耗时
- 失败数量和失败原因分类

### 指标最少要求
- `parse_duration_ms`
- `chunk_count`
- `stage1_request_count`
- `stage1_success_count`
- `stage2_duration_ms`
- `render_success_count`
- `render_failure_count`

---

## 测试与验证策略

### 本地优先
按照仓库约定，自动化实现阶段优先做 compile-only 和 CLI 验证，不默认启动 iOS Simulator。

### 建议验证顺序
1. `swift build`
2. `swift run lanread-batch --help`
3. 使用测试 EPUB 跑单本 `generate`
4. 检查 `manifest.json` 和 `images/`
5. 对失败场景做一次重跑测试

### 后续测试建议
- 为切块逻辑增加单元测试
- 为 stage 1 / stage 2 响应解析增加单元测试
- 为 manifest schema 增加快照测试
- 为渲染输出增加基础尺寸和非空验证

---

## 成功标准

### MVP 完成标准
- 单本 EPUB 可以在 macOS CLI 中完整跑通
- 能稳定输出 10 到 20 张图片
- 产物目录结构固定
- manifest 可追溯到章节和 excerpt
- 整体流程不依赖 iOS App 前台运行

### 第一阶段失败标准
以下任一出现，说明方案还不能进入下一阶段：

- 必须依赖 iOS App 才能跑通
- 无法稳定重跑
- 无法追溯图片来源
- 输出图片质量明显不可用
- 大量候选并非直接摘自原文

---

## 当前建议实现顺序
1. 建立 Package 和 CLI 空壳。
2. 跑通 EPUB 解析到 `excerpts.jsonl`。
3. 接入 stage 1 AI 抽取。
4. 加入候选聚合和 stage 2 筛选。
5. 完成 macOS 分享图渲染。
6. 写出 manifest / logs / metrics。
7. 再做目录批处理和后续 caption / publish 预留。

## 开放问题
- `EPubParser` 是直接跨 target 复用，还是抽出公共模块？
- 分享图是否需要强依赖封面图，没有封面时如何降级？
- 多语言书籍混排时，窗口长度应按字符还是按 token 粗估？
- `publish` 阶段未来是否由 CLI 直连社媒 API，还是交给上层 orchestrator？
- 是否需要在 manifest 中记录 prompt version，以便后续追溯生成质量？

## 下一步
进入 P0：创建 `Package.swift`、基础 targets 和 `generate` 命令骨架。
