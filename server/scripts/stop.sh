#!/usr/bin/env bash
# Stop the Isla Reader server container. Optional --remove to delete it.
# Usage: ./server/scripts/stop.sh [--remove|-r]

set -euo pipefail

remove_container=false
for arg in "$@"; do
  case "$arg" in
    --remove|-r) remove_container=true ;;
    *) echo "未知参数: $arg" >&2; exit 1 ;;
  esac
done

CONTAINER_NAME="${CONTAINER_NAME:-isla-reader-server}"

echo "Stopping container ${CONTAINER_NAME}..."
docker stop "${CONTAINER_NAME}" 2>/dev/null || {
  echo "容器未运行或不存在。" >&2
}

if [[ "$remove_container" == true ]]; then
  echo "Removing container ${CONTAINER_NAME}..."
  docker rm "${CONTAINER_NAME}" 2>/dev/null || true
fi
