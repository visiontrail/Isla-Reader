#!/usr/bin/env bash
# Generate a self-signed TLS certificate for the LanRead server.
# Usage: ./server/scripts/generate-cert.sh [-n CN|--name CN] [--ip IPv4] [-d DAYS|--days DAYS] [--force]

set -euo pipefail

common_name="localhost"
days="${DAYS:-365}"
force_overwrite=false
ip_sans=()
cert_uid="${CERT_UID:-1000}"
cert_gid="${CERT_GID:-1000}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--name)
      common_name="$2"
      shift 2
      ;;
    --ip)
      ip_sans+=("$2")
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
      echo "用法: $0 [-n CN|--name CN] [--ip IPv4] [-d DAYS|--days DAYS] [--force]" >&2
      exit 1
      ;;
  esac
done

is_ipv4() {
  local ip="$1"
  if [[ ! "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    return 1
  fi
  IFS='.' read -r o1 o2 o3 o4 <<<"$ip"
  for octet in "$o1" "$o2" "$o3" "$o4"; do
    if ((octet < 0 || octet > 255)); then
      return 1
    fi
  done
  return 0
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
cert_dir="${CERT_DIR:-${repo_root}/certs}"
key_path="${cert_dir}/server.key"
cert_path="${cert_dir}/server.crt"

mkdir -p "${cert_dir}"

san_entries=()
if is_ipv4 "$common_name"; then
  san_entries+=("IP:${common_name}")
else
  san_entries+=("DNS:${common_name}")
fi

for ip in "${ip_sans[@]}"; do
  if ! is_ipv4 "$ip"; then
    echo "无效 IP 地址: $ip" >&2
    exit 1
  fi
  san_entries+=("IP:${ip}")
done

# 便于本机测试，默认包含 127.0.0.1
san_entries+=("IP:127.0.0.1")

san_value=$(IFS=,; echo "${san_entries[*]}")

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
  -addext "subjectAltName = ${san_value}" \
  -addext "keyUsage = critical, digitalSignature, keyEncipherment" \
  -addext "extendedKeyUsage = serverAuth"

chmod 640 "${key_path}" "${cert_path}" || true

if [[ "$(id -u)" -eq 0 ]]; then
  chown "${cert_uid}:${cert_gid}" "${key_path}" "${cert_path}" || true
else
  echo "提示: 非 root 运行，若使用 Docker，请确保 TLS 文件可被容器用户 (默认 uid/gid=${cert_uid}:${cert_gid}) 读取。" >&2
fi

echo "证书已生成："
echo "  私钥: ${key_path}"
echo "  证书: ${cert_path}"
