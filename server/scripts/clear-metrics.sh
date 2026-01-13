#!/usr/bin/env bash
# Clear all persisted metrics data for the LanRead server.
# Usage: ./server/scripts/clear-metrics.sh

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
env_file="${ENV_FILE:-${repo_root}/.env}"

if [[ -f "$env_file" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
else
  echo "警告: 未找到环境文件 ${env_file}，将使用默认路径 data/metrics.jsonl" >&2
fi

metrics_path="${ISLA_METRICS_DATA_FILE:-data/metrics.jsonl}"

if [[ "$metrics_path" != /* ]]; then
  metrics_path="${repo_root}/app/${metrics_path}"
fi

echo "指标数据文件路径: ${metrics_path}"
mkdir -p "$(dirname "$metrics_path")"

if [[ -f "$metrics_path" ]]; then
  : > "$metrics_path"
  echo "已清空统计数据文件。"
else
  : > "$metrics_path"
  echo "指标文件不存在，已创建空文件。"
fi

echo "完成。若服务正在运行，请重启以清空内存中的缓存。"
