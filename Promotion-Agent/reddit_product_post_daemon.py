#!/usr/bin/env python3
"""
Run a Claude Reddit promotion prompt at random times during the night.

This script is intentionally dependency-free so it can keep running for long
periods with only the system Python installed.
"""

from __future__ import annotations

import logging
import random
import signal
import subprocess
import sys
import time
from datetime import datetime, time as day_time, timedelta
from pathlib import Path
from typing import Iterable, Optional


# ===== Editable settings =====

# Active window. This supports crossing midnight, e.g. 22:30 -> 08:00.
WINDOW_START = "22:30"
WINDOW_END = "08:40"

# How many times to run the command per active window.
RUNS_PER_WINDOW = 15

# Set to None for fully random placement across the window, or use a positive
# number to avoid executions being too close together.
MIN_SECONDS_BETWEEN_RUNS: Optional[int] = 60

# Claude command configuration.
CLAUDE_BINARY = "claude"
CLAUDE_ARGS = ["--dangerously-skip-permissions"]
PROMPT = (
    "请你使用 /reddit-post 在Reddit中的r/selfimprovement或r/productivity中浏览你认为有价值的1个帖子，"
    "并且回复他，你在想要回复的帖子中 需要确认是否已经有“Spirited-Client7012”"
    "也就是你账号的名字已经回复过的帖子，切记不要再次回复"
)

# Runtime behavior.
# Hard upper bound (seconds) for a single Claude run.  When the schedule
# provides a tighter deadline (next run - TIMEOUT_BUFFER_SECONDS), that
# tighter value is used instead.  Set to None to rely solely on the
# schedule-derived deadline.
COMMAND_TIMEOUT_SECONDS: Optional[int] = 45 * 60  # 45 minutes absolute max

# Seconds to reserve before the next scheduled run so the process is
# guaranteed to finish before the next one starts.
TIMEOUT_BUFFER_SECONDS: int = 3 * 60  # 3 minutes

WORKING_DIRECTORY = Path(__file__).resolve().parent
LOG_FILE = WORKING_DIRECTORY / "reddit_claude_daemon.log"
DRY_RUN = False


# ===== Program logic =====

SHOULD_STOP = False


def configure_logging() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        handlers=[
            logging.FileHandler(LOG_FILE, encoding="utf-8"),
            logging.StreamHandler(sys.stdout),
        ],
    )


def handle_stop_signal(signum: int, _frame: object) -> None:
    global SHOULD_STOP
    SHOULD_STOP = True
    logging.info("Received signal %s, stopping after the current step.", signum)


def parse_clock(value: str) -> day_time:
    hour_text, minute_text = value.split(":", maxsplit=1)
    return day_time(hour=int(hour_text), minute=int(minute_text))


def window_for(now: datetime) -> tuple[datetime, datetime]:
    start_clock = parse_clock(WINDOW_START)
    end_clock = parse_clock(WINDOW_END)

    today_start = datetime.combine(now.date(), start_clock)
    today_end = datetime.combine(now.date(), end_clock)

    if start_clock < end_clock:
        return today_start, today_end

    if now.time() < end_clock:
        return today_start - timedelta(days=1), today_end

    return today_start, today_end + timedelta(days=1)


def next_window_after(now: datetime) -> tuple[datetime, datetime]:
    start, end = window_for(now)
    if now < start:
        return start, end
    if now < end:
        return start, end

    next_day = now.date() + timedelta(days=1)
    next_start = datetime.combine(next_day, parse_clock(WINDOW_START))
    next_end = datetime.combine(next_day, parse_clock(WINDOW_END))
    if parse_clock(WINDOW_START) >= parse_clock(WINDOW_END):
        next_end += timedelta(days=1)
    return next_start, next_end


def sleep_until(target: datetime) -> None:
    while not SHOULD_STOP:
        seconds = (target - datetime.now()).total_seconds()
        if seconds <= 0:
            return
        time.sleep(min(seconds, 60))


def random_schedule(start: datetime, end: datetime, count: int) -> list[datetime]:
    if count <= 0:
        return []

    total_seconds = max(0, int((end - start).total_seconds()))
    if total_seconds <= 0:
        return []

    min_gap = MIN_SECONDS_BETWEEN_RUNS or 0
    if min_gap > 0 and min_gap * (count - 1) > total_seconds:
        logging.warning(
            "MIN_SECONDS_BETWEEN_RUNS is too large for the remaining window; "
            "falling back to unconstrained random schedule."
        )
        min_gap = 0

    if min_gap <= 0:
        offsets = sorted(random.sample(range(total_seconds + 1), k=min(count, total_seconds + 1)))
        while len(offsets) < count:
            offsets.append(random.randint(0, total_seconds))
        return [start + timedelta(seconds=offset) for offset in sorted(offsets)]

    available = total_seconds - min_gap * (count - 1)
    offsets = sorted(random.sample(range(available + 1), k=min(count, available + 1)))
    while len(offsets) < count:
        offsets.append(random.randint(0, available))
    return [
        start + timedelta(seconds=offset + index * min_gap)
        for index, offset in enumerate(sorted(offsets))
    ]


def command() -> list[str]:
    return [CLAUDE_BINARY, *CLAUDE_ARGS, "-p", PROMPT]


def format_command(parts: Iterable[str]) -> str:
    return " ".join(repr(part) if " " in part else part for part in parts)


def run_claude(run_index: int, total_runs: int, deadline: Optional[datetime] = None) -> None:
    cmd = command()
    logging.info("Run %s/%s: %s", run_index, total_runs, format_command(cmd))

    if DRY_RUN:
        logging.info("DRY_RUN is enabled; command was not executed.")
        return

    # Compute effective timeout: tightest of the hard cap and the schedule deadline.
    effective_timeout: Optional[float] = None
    if deadline is not None:
        seconds_until_deadline = (deadline - datetime.now()).total_seconds()
        if seconds_until_deadline <= 0:
            logging.warning(
                "Run %s/%s: deadline already passed, skipping.", run_index, total_runs
            )
            return
        effective_timeout = seconds_until_deadline
    if COMMAND_TIMEOUT_SECONDS is not None:
        effective_timeout = (
            min(effective_timeout, COMMAND_TIMEOUT_SECONDS)
            if effective_timeout is not None
            else float(COMMAND_TIMEOUT_SECONDS)
        )

    if effective_timeout is not None:
        logging.info(
            "Run %s/%s: timeout set to %.0f seconds.", run_index, total_runs, effective_timeout
        )

    try:
        completed = subprocess.run(
            cmd,
            cwd=WORKING_DIRECTORY,
            text=True,
            capture_output=True,
            timeout=effective_timeout,
            check=False,
        )
    except FileNotFoundError:
        logging.exception("Claude command not found: %s", CLAUDE_BINARY)
        return
    except subprocess.TimeoutExpired as exc:
        out = (exc.stdout or b"").decode(errors="replace").strip() if isinstance(exc.stdout, bytes) else (exc.stdout or "").strip()
        if out:
            logging.info("stdout (partial):\n%s", out)
        logging.error(
            "Run %s/%s timed out after %.0f seconds and was killed.",
            run_index, total_runs, effective_timeout,
        )
        return
    except Exception:
        logging.exception("Claude command failed before completion.")
        return

    if completed.stdout.strip():
        logging.info("stdout:\n%s", completed.stdout.strip())
    if completed.stderr.strip():
        logging.warning("stderr:\n%s", completed.stderr.strip())

    if completed.returncode == 0:
        logging.info("Run %s/%s completed successfully.", run_index, total_runs)
    else:
        logging.error("Run %s/%s exited with code %s.", run_index, total_runs, completed.returncode)


def run_window(start: datetime, end: datetime) -> None:
    schedule_start = max(datetime.now(), start)
    schedule = random_schedule(schedule_start, end, RUNS_PER_WINDOW)

    logging.info(
        "Active window: %s -> %s, scheduled %s run(s).",
        start.isoformat(sep=" ", timespec="minutes"),
        end.isoformat(sep=" ", timespec="minutes"),
        len(schedule),
    )
    for index, scheduled_at in enumerate(schedule, start=1):
        if SHOULD_STOP:
            return
        # Deadline = next scheduled run (minus buffer), or window end for the last run.
        if index < len(schedule):
            next_run_at = schedule[index]  # schedule is 0-based; index is already +1
            deadline = next_run_at - timedelta(seconds=TIMEOUT_BUFFER_SECONDS)
        else:
            deadline = end - timedelta(seconds=TIMEOUT_BUFFER_SECONDS)
        logging.info("Next run %s/%s scheduled at %s.", index, len(schedule), scheduled_at)
        sleep_until(scheduled_at)
        if SHOULD_STOP:
            return
        run_claude(index, len(schedule), deadline=deadline)


def main() -> int:
    configure_logging()
    signal.signal(signal.SIGINT, handle_stop_signal)
    signal.signal(signal.SIGTERM, handle_stop_signal)

    logging.info("Reddit Claude daemon started. Log file: %s", LOG_FILE)

    last_window_start: Optional[datetime] = None
    while not SHOULD_STOP:
        now = datetime.now()
        start, end = next_window_after(now)

        if now < start:
            logging.info("Outside active window. Sleeping until %s.", start)
            sleep_until(start)
            continue

        if last_window_start == start:
            sleep_until(end)
            continue

        last_window_start = start
        run_window(start, end)

    logging.info("Reddit Claude daemon stopped.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
