---
name: generate-promotion
description: 从 EPUB 文件批量生成高亮分享图片（PNG），用于社交媒体推广内容制作。当用户提到要为某本书生成推广素材、分享卡、高亮图、Promotion 内容，或提到运行 lanread-batch / generate-promotion 时，应使用此 skill。
---

# Generate Promotion Skill

从 EPUB 文件中提取高质量书摘，批量渲染成分享卡图片（PNG），产物保存在 `Promotion/` 目录下，供社交媒体发布使用。

## 调用入口

使用项目根目录下的封装脚本，**无需了解底层 `lanread-batch` 命令细节**：

```
Promotion-Agent/generate-promotion.sh
```

## 最简调用（只需 EPUB 路径）

```bash
./Promotion-Agent/generate-promotion.sh --epub "/path/to/book.epub"
```

输出目录自动生成为 `Promotion/<YYYYMMDD>-<book-slug>/`。

## 全部可用参数

| 参数 | 默认值 | 说明 |
|---|---|---|
| `--epub` | **必填** | EPUB 文件路径（绝对路径或相对于项目根目录） |
| `--output` | `Promotion/<日期>-<书名slug>` | 输出目录 |
| `--highlights` | `30` | 目标高亮数量 |
| `--language` | `en` | 输出语言（`en` / `zh-Hans` / `ja` 等） |
| `--style` | `white` | 分享卡样式：`none` / `white` / `black` |
| `--profile-name` | `LeoGuo` | 分享卡署名 |
| `--profile-avatar` | `~/Downloads/Flamingo.png` | 头像图片路径 |
| `--timezone` | `America/New_York` | 时区标识符 |
| `--provider-config` | `Batch/ai.json` | AI provider 配置 JSON 路径 |

## 产物结构

每次运行后，输出目录包含：

```
Promotion/<date>-<book-slug>/
├── images/
│   ├── 001-highlight-title.png   # 高亮分享图
│   └── ...
├── manifest.json                 # 完整产物清单
├── selected.stage2.json          # 最终入选高亮列表
└── logs/
    ├── run.log                   # 运行日志
    └── metrics.json              # 各阶段指标
```

## 工作流程

运行时内部经历五个阶段：

1. **EPUB 解析** — 提取书籍文本与元数据
2. **文本切块** — 将正文分割成适合分享的窗口（`excerpts.jsonl`）
3. **AI Stage 1** — 从全书候选里抽取高质量书摘（`candidates.stage1.jsonl`）
4. **AI Stage 2** — 排序筛选最终入选高亮（`selected.stage2.json`）
5. **渲染** — 将高亮渲染为 PNG 分享图（`images/*.png`）

AI 调用依赖 `Batch/ai.json` 中的配置。若 Stage 1/2 失败，自动降级为本地排序继续产出。

## 使用示例

### 为一本英文书生成推广素材

```bash
./Promotion-Agent/generate-promotion.sh \
  --epub "/Users/guoliang/Downloads/10x-is-easier-than-2x.epub"
```

### 指定输出目录和语言

```bash
./Promotion-Agent/generate-promotion.sh \
  --epub "/Users/guoliang/Downloads/atomic-habits.epub" \
  --output "Promotion/20260502-atomic-habits" \
  --language en \
  --highlights 20
```

### 中文书籍

```bash
./Promotion-Agent/generate-promotion.sh \
  --epub "/path/to/chinese-book.epub" \
  --language zh-Hans \
  --highlights 15
```

## 注意事项

- 脚本必须在**项目根目录**执行（`swift run` 依赖 `Package.swift`）
- 首次运行会编译 Swift Package，耗时约 1–3 分钟；后续增量编译较快
- AI 阶段依赖 `Batch/ai.json` 中的 endpoint 与 API key，网络不通时自动降级
- `--profile-avatar` 或 `--provider-config` 指定的文件不存在时，脚本会自动跳过该参数，不会报错中断
