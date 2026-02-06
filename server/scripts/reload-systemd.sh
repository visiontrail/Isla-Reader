#!/usr/bin/env bash
# Pull latest code, install dependencies, and restart the systemd service.
# Usage: ./server/scripts/reload-systemd.sh [branch]

set -euo pipefail

SERVICE_NAME="${SERVICE_NAME:-isla-api}"
REPO_DIR="${REPO_DIR:-/home/ec2-user/Isla-Reader}"
APP_DIR="${APP_DIR:-${REPO_DIR}/server}"
VENV_PYTHON="${VENV_PYTHON:-${APP_DIR}/.venv/bin/python}"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:8000/health}"
TARGET_BRANCH="${1:-}"

run_systemctl() {
  if [[ "$(id -u)" -eq 0 ]]; then
    systemctl "$@"
    return
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo systemctl "$@"
    return
  fi

  systemctl "$@"
}

if [[ ! -d "$REPO_DIR/.git" ]]; then
  echo "仓库目录不存在或不是 Git 仓库: $REPO_DIR" >&2
  exit 1
fi

if [[ ! -f "$VENV_PYTHON" ]]; then
  echo "找不到 Python 虚拟环境: $VENV_PYTHON" >&2
  exit 1
fi

cd "$REPO_DIR"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "检测到未提交的本地修改，已停止部署以避免覆盖。" >&2
  echo "请先处理修改（提交 / stash）后重试。" >&2
  exit 1
fi

if [[ -z "$TARGET_BRANCH" ]]; then
  TARGET_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
fi

echo "更新代码分支: ${TARGET_BRANCH}"
git fetch --all --prune
if git show-ref --verify --quiet "refs/heads/${TARGET_BRANCH}"; then
  git checkout "$TARGET_BRANCH"
else
  git checkout -b "$TARGET_BRANCH" "origin/$TARGET_BRANCH"
fi
git pull --ff-only origin "$TARGET_BRANCH"

echo "安装/更新 Python 依赖..."
"$VENV_PYTHON" -m pip install --upgrade pip
"$VENV_PYTHON" -m pip install -e "$APP_DIR"

echo "重载 systemd 并重启服务: ${SERVICE_NAME}"
run_systemctl daemon-reload
run_systemctl restart "$SERVICE_NAME"

echo "服务状态（前 25 行）:"
run_systemctl --no-pager --full status "$SERVICE_NAME" | sed -n '1,25p'

if command -v curl >/dev/null 2>&1; then
  echo "健康检查: ${HEALTH_URL}"
  curl --fail --silent --show-error "$HEALTH_URL" >/dev/null
  echo "健康检查通过。"
else
  echo "未找到 curl，跳过健康检查。"
fi

echo "部署完成。"
