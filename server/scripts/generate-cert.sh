#!/usr/bin/env bash
# Generate a self-signed TLS certificate for the Isla Reader server.
# Usage: ./server/scripts/generate-cert.sh [-n CN|--name CN] [-d DAYS|--days DAYS] [--force]

set -euo pipefail

common_name="localhost"
days="${DAYS:-365}"
force_overwrite=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--name)
      common_name="$2"
      shift 2
      ;;
    -d|--days)
      days="$2"
      shift 2
      ;;
    -f|--force)
      force_overwrite=true
      shift
      ;;
    *)
      echo "未知参数: $1" >&2
      echo "用法: $0 [-n CN|--name CN] [-d DAYS|--days DAYS] [--force]" >&2
      exit 1
      ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
cert_dir="${CERT_DIR:-${repo_root}/certs}"
key_path="${cert_dir}/server.key"
cert_path="${cert_dir}/server.crt"

mkdir -p "${cert_dir}"

if [[ -f "$key_path" || -f "$cert_path" ]]; then
  if [[ "$force_overwrite" == false ]]; then
    echo "证书或私钥已存在于 ${cert_dir}，使用 --force 重新生成。" >&2
    exit 1
  fi
  rm -f "$key_path" "$cert_path"
fi

echo "生成自签名证书：CN=${common_name}, 有效期 ${days} 天"
openssl req -x509 -nodes -days "${days}" -newkey rsa:2048 \
  -keyout "${key_path}" \
  -out "${cert_path}" \
  -subj "/CN=${common_name}" \
  -addext "subjectAltName = DNS:${common_name},IP:127.0.0.1" \
  -addext "keyUsage = critical, digitalSignature, keyEncipherment" \
  -addext "extendedKeyUsage = serverAuth"

echo "证书已生成："
echo "  私钥: ${key_path}"
echo "  证书: ${cert_path}"
