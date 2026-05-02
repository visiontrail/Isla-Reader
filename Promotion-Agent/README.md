# Promotion Agent

## 高亮分享图生成（`generate-promotion.sh`）

封装了 `swift run lanread-batch generate`，预置了常用默认值，供 AI Agent 或手动执行调用。

### 最简调用（只传 epub 路径）

```bash
./Promotion-Agent/generate-promotion.sh --epub "/path/to/book.epub"
```

输出目录自动生成为 `Promotion/<YYYYMMDD>-<book-slug>/`，包含 `images/*.png`、`manifest.json` 等。

### 完整参数

| 参数 | 默认值 | 说明 |
|---|---|---|
| `--epub` | 必填 | EPUB 文件路径 |
| `--output` | `Promotion/<date>-<slug>` | 输出目录 |
| `--highlights` | `30` | 目标高亮数量 |
| `--language` | `en` | 输出语言（`en` / `zh-Hans` / `ja` …） |
| `--style` | `white` | 分享卡样式：`none` / `white` / `black` |
| `--profile-name` | `LeoGuo` | 分享卡署名 |
| `--profile-avatar` | `~/Downloads/Flamingo.png` | 头像图片路径 |
| `--timezone` | `America/New_York` | 时区 |
| `--provider-config` | `Batch/ai.json` | AI provider 配置 JSON |

### 完整调用示例

```bash
./Promotion-Agent/generate-promotion.sh \
  --epub "/Users/guoliang/Downloads/some-book.epub" \
  --output "Promotion/20260502-some-book" \
  --highlights 30 \
  --language en \
  --style white \
  --profile-name "LeoGuo" \
  --profile-avatar "/Users/guoliang/Downloads/Flamingo.png" \
  --timezone "America/New_York"
```

---

`reddit_claude_daemon.py` 会长期运行，并在每天 `22:30` 到次日 `08:00` 的时间窗口内随机执行 Claude 命令。

## 启动

```bash
cd Promotion-Agent
./reddit_claude_daemon.py
```

后台运行示例：

```bash
cd Promotion-Agent
nohup ./reddit_claude_daemon.py > reddit_claude_daemon.nohup.log 2>&1 &
```

## 常用配置

直接编辑 `reddit_claude_daemon.py` 顶部的变量：

- `WINDOW_START` / `WINDOW_END`: 执行时间窗口，默认 `22:30` 到 `08:00`
- `RUNS_PER_WINDOW`: 每个窗口执行次数，默认 `15`
- `MIN_SECONDS_BETWEEN_RUNS`: 两次执行之间的最小间隔秒数，默认 `60`
- `PROMPT`: `claude -p` 使用的提示词
- `DRY_RUN`: 改成 `True` 时只写日志，不真正执行命令

运行日志写入 `reddit_claude_daemon.log`。
