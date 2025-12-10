#!/usr/bin/env bash
set -euo pipefail

host="${UVICORN_HOST:-0.0.0.0}"
port="${PORT:-8443}"
workers="${UVICORN_WORKERS:-1}"
require_https="${ISLA_REQUIRE_HTTPS:-true}"
ssl_cert="${SSL_CERTFILE:-}"
ssl_key="${SSL_KEYFILE:-}"

if [[ "${require_https,,}" != "false" ]]; then
  if [[ -z "$ssl_cert" || -z "$ssl_key" ]]; then
    echo "ISLA_REQUIRE_HTTPS=true 但未提供 SSL_CERTFILE/SSL_KEYFILE" >&2
    exit 1
  fi
  for file in "$ssl_cert" "$ssl_key"; do
    if [[ ! -f "$file" ]]; then
      echo "缺少 TLS 文件: $file" >&2
      exit 1
    fi
  done
  exec uvicorn app.main:app \
    --host "$host" \
    --port "$port" \
    --workers "$workers" \
    --ssl-certfile "$ssl_cert" \
    --ssl-keyfile "$ssl_key" \
    --proxy-headers
else
  exec uvicorn app.main:app \
    --host "$host" \
    --port "$port" \
    --workers "$workers" \
    --proxy-headers
fi
