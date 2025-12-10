#!/usr/bin/env bash
# Build and run the Isla Reader server container on a clean host.
# Usage: ./server/scripts/deploy.sh

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

IMAGE_NAME="${IMAGE_NAME:-isla-reader-server}"
CONTAINER_NAME="${CONTAINER_NAME:-isla-reader-server}"
HOST_PORT="${HOST_PORT:-8443}"
CERT_DIR="${CERT_DIR:-${repo_root}/certs}"
ENV_FILE="${ENV_FILE:-${repo_root}/.env}"

SSL_CERTFILE="${SSL_CERTFILE:-/certs/server.crt}"
SSL_KEYFILE="${SSL_KEYFILE:-/certs/server.key}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "缺少环境文件: $ENV_FILE" >&2
  exit 1
fi

if [[ ! -d "$CERT_DIR" ]]; then
  echo "缺少证书目录: $CERT_DIR" >&2
  echo "请将 server.key/server.crt 放在该目录或设置 CERT_DIR" >&2
  exit 1
fi

echo "Building image ${IMAGE_NAME}..."
docker build --pull -t "${IMAGE_NAME}" "${repo_root}"

echo "Stopping any existing container ${CONTAINER_NAME}..."
docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true

echo "Starting container ${CONTAINER_NAME}..."
docker run -d \
  --name "${CONTAINER_NAME}" \
  --env-file "${ENV_FILE}" \
  -e SSL_CERTFILE="${SSL_CERTFILE}" \
  -e SSL_KEYFILE="${SSL_KEYFILE}" \
  -p "${HOST_PORT}:8443" \
  -v "${CERT_DIR}:/certs:ro" \
  "${IMAGE_NAME}"

echo "Container ${CONTAINER_NAME} is running on port ${HOST_PORT}."
