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
CERT_UID="${CERT_UID:-1000}"
CERT_GID="${CERT_GID:-1000}"

SSL_CERTFILE="${SSL_CERTFILE:-/certs/server.crt}"
SSL_KEYFILE="${SSL_KEYFILE:-/certs/server.key}"
cert_filename="$(basename "$SSL_CERTFILE")"
key_filename="$(basename "$SSL_KEYFILE")"
host_cert_path="${CERT_DIR}/${cert_filename}"
host_key_path="${CERT_DIR}/${key_filename}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "缺少环境文件: $ENV_FILE" >&2
  exit 1
fi

if [[ ! -d "$CERT_DIR" ]]; then
  echo "缺少证书目录: $CERT_DIR" >&2
  echo "请将 server.key/server.crt 放在该目录或设置 CERT_DIR" >&2
  exit 1
fi

if [[ ! -f "$host_cert_path" ]]; then
  echo "缺少证书文件: $host_cert_path" >&2
  exit 1
fi

if [[ ! -f "$host_key_path" ]]; then
  echo "缺少私钥文件: $host_key_path" >&2
  exit 1
fi

ensure_tls_permissions() {
  local cert_path="$1"
  local key_path="$2"

  if [[ "$(id -u)" -eq 0 ]]; then
    chown "${CERT_UID}:${CERT_GID}" "$cert_path" "$key_path" || true
    chmod 640 "$cert_path" "$key_path"
  else
    if ! chmod 640 "$cert_path" "$key_path" 2>/dev/null; then
      echo "无法修改 TLS 权限，请确保容器用户 (uid=${CERT_UID}) 可读取 ${CERT_DIR}" >&2
    fi
  fi

  for path in "$cert_path" "$key_path"; do
    if [[ ! -r "$path" ]]; then
      echo "TLS 文件不可读: $path" >&2
      echo "请运行: sudo chown ${CERT_UID}:${CERT_GID} ${CERT_DIR}/$(basename "$path") && chmod 640 ${CERT_DIR}/$(basename "$path")" >&2
      exit 1
    fi
  done
}

ensure_tls_permissions "$host_cert_path" "$host_key_path"

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
