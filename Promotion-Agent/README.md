# Promotion Agent

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
