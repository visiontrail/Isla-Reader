#!/usr/bin/env bash
# Quick local launcher for the server landing page with health checks.
# Usage: ./server/scripts/start-local-web.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8000}"
OPEN_BROWSER="${OPEN_BROWSER:-1}"
INSTALL_DEPS="${INSTALL_DEPS:-auto}" # auto | always | never
FORCE_HTTP="${FORCE_HTTP:-1}" # 1 = force ISLA_REQUIRE_HTTPS=false for local validation

HEALTH_URL="http://${HOST}:${PORT}/health"
HOME_URL="http://${HOST}:${PORT}/"

log() {
  printf '[start-local-web] %s\n' "$*"
}

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 未安装，无法启动。" >&2
  exit 1
fi

if command -v lsof >/dev/null 2>&1; then
  if lsof -iTCP:"${PORT}" -sTCP:LISTEN -n -P >/dev/null 2>&1; then
    echo "端口 ${PORT} 已被占用，请先释放端口或改用 PORT=xxxx。" >&2
    exit 1
  fi
fi

cd "${SERVER_DIR}"

if [[ ! -d .venv ]]; then
  log "创建虚拟环境 .venv"
  python3 -m venv .venv
fi

VENV_PYTHON="${SERVER_DIR}/.venv/bin/python"
if [[ ! -x "${VENV_PYTHON}" ]]; then
  echo "虚拟环境损坏：${VENV_PYTHON} 不可执行。" >&2
  exit 1
fi

deps_ready=false
if "${VENV_PYTHON}" - <<'PY' >/dev/null 2>&1
import fastapi
import uvicorn
import pydantic_settings
import httpx
PY
then
  deps_ready=true
fi

if [[ "${INSTALL_DEPS}" == "always" ]]; then
  log "安装依赖 (INSTALL_DEPS=always)"
  "${VENV_PYTHON}" -m pip install -e .
elif [[ "${deps_ready}" == "false" && "${INSTALL_DEPS}" == "auto" ]]; then
  log "检测到缺少依赖，开始安装"
  "${VENV_PYTHON}" -m pip install -e .
elif [[ "${deps_ready}" == "false" && "${INSTALL_DEPS}" == "never" ]]; then
  echo "缺少依赖且 INSTALL_DEPS=never。请先手动执行: ${VENV_PYTHON} -m pip install -e ${SERVER_DIR}" >&2
  exit 1
else
  log "依赖已满足，跳过安装"
fi

if [[ -f .env ]]; then
  # shellcheck disable=SC1091
  set -a
  source .env
  set +a
fi

# Provide safe defaults for local page/health validation.
: "${ISLA_API_KEY:=local-dev-key}"
: "${ISLA_API_ENDPOINT:=https://example.com/v1}"
: "${ISLA_AI_MODEL:=qwen-flash}"
: "${ISLA_CLIENT_ID:=ios-LanRead}"
: "${ISLA_CLIENT_SECRET:=local-dev-secret}"

if [[ "${FORCE_HTTP}" == "1" ]]; then
  ISLA_REQUIRE_HTTPS=false
else
  : "${ISLA_REQUIRE_HTTPS:=false}"
fi

export ISLA_API_KEY
export ISLA_API_ENDPOINT
export ISLA_AI_MODEL
export ISLA_CLIENT_ID
export ISLA_CLIENT_SECRET
export ISLA_REQUIRE_HTTPS

cleanup() {
  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
    log "停止服务 (PID=${SERVER_PID})"
    kill "${SERVER_PID}" >/dev/null 2>&1 || true
    wait "${SERVER_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

log "启动服务: ${HOME_URL}"
"${VENV_PYTHON}" -m uvicorn app.main:app --host "${HOST}" --port "${PORT}" --no-access-log &
SERVER_PID=$!

for _ in {1..30}; do
  if curl --fail --silent "${HEALTH_URL}" >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done

if ! curl --fail --silent "${HEALTH_URL}" >/dev/null 2>&1; then
  echo "健康检查失败: ${HEALTH_URL}" >&2
  exit 1
fi

home_html="$(curl --fail --silent "${HOME_URL}")"
if ! grep -q "Lan Read" <<<"${home_html}"; then
  echo "首页验证失败: ${HOME_URL} 未返回预期内容。" >&2
  exit 1
fi

log "验证通过"
log "health: ${HEALTH_URL}"
log "home:   ${HOME_URL}"

if [[ "${OPEN_BROWSER}" == "1" ]] && command -v open >/dev/null 2>&1; then
  open "${HOME_URL}" >/dev/null 2>&1 || true
fi

log "按 Ctrl+C 停止服务"
wait "${SERVER_PID}"
