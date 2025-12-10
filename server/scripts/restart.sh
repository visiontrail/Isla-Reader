#!/usr/bin/env bash
# Rebuild and restart the Isla Reader server container with the latest code.
# Usage: ./server/scripts/restart.sh

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${script_dir}/deploy.sh"
