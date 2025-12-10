#!/usr/bin/env bash
# Generate a strong random client secret for Isla Reader secure server HMAC signing.
# Usage: ./scripts/generate_client_secret.sh

set -euo pipefail

# 32 random bytes -> 64 hex chars. Increase count for longer secrets.
SECRET="$(python3 - <<'PY'
import secrets
print(secrets.token_hex(32))
PY
)"

echo "$SECRET"
