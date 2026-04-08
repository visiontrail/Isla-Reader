#!/bin/bash

################################################################################
# LanRead - Batch EPUB generate wrapper
# Usage: ./scripts/batch-generate.sh --input-dir <path> [options]
################################################################################

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
cd "$PROJECT_DIR"

usage() {
    cat <<'EOF'
Usage:
  ./scripts/batch-generate.sh --input-dir <path> [options]

Required:
  --input-dir <path>         Directory to scan EPUB files recursively.

Optional:
  --output <path>            Output root directory. Default: ./build/batch-output
  --highlights <count>       Target highlights per book. Default: 20
  --language <code>          Output language. Default: zh-Hans
  --style <value>            Share card style: none | white | black. Default: white
  --profile-name <name>      Share card user name. Default: Reader
  --profile-avatar <path>    Avatar image path (png/jpg/webp)
  --provider-config <path>   AI provider config json path.
  --overwrite-policy <mode>  resume | replace. Default: resume
  -h, --help                 Show help.
EOF
}

INPUT_DIR=""
OUTPUT_DIR="$PROJECT_DIR/build/batch-output"
HIGHLIGHTS="20"
LANGUAGE="zh-Hans"
STYLE="white"
OVERWRITE_POLICY="resume"
PROVIDER_CONFIG=""
PROFILE_NAME="Reader"
PROFILE_AVATAR=""
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --input-dir)
            [[ $# -ge 2 ]] || { echo "Missing value for --input-dir" >&2; exit 64; }
            INPUT_DIR="$2"
            shift 2
            ;;
        --output)
            [[ $# -ge 2 ]] || { echo "Missing value for --output" >&2; exit 64; }
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --highlights)
            [[ $# -ge 2 ]] || { echo "Missing value for --highlights" >&2; exit 64; }
            HIGHLIGHTS="$2"
            shift 2
            ;;
        --language)
            [[ $# -ge 2 ]] || { echo "Missing value for --language" >&2; exit 64; }
            LANGUAGE="$2"
            shift 2
            ;;
        --style)
            [[ $# -ge 2 ]] || { echo "Missing value for --style" >&2; exit 64; }
            STYLE="$2"
            shift 2
            ;;
        --provider-config)
            [[ $# -ge 2 ]] || { echo "Missing value for --provider-config" >&2; exit 64; }
            PROVIDER_CONFIG="$2"
            shift 2
            ;;
        --profile-name)
            [[ $# -ge 2 ]] || { echo "Missing value for --profile-name" >&2; exit 64; }
            PROFILE_NAME="$2"
            shift 2
            ;;
        --profile-avatar)
            [[ $# -ge 2 ]] || { echo "Missing value for --profile-avatar" >&2; exit 64; }
            PROFILE_AVATAR="$2"
            shift 2
            ;;
        --overwrite-policy)
            [[ $# -ge 2 ]] || { echo "Missing value for --overwrite-policy" >&2; exit 64; }
            OVERWRITE_POLICY="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            EXTRA_ARGS+=("$@")
            break
            ;;
        *)
            EXTRA_ARGS+=("$1")
            shift
            ;;
    esac
done

if [[ -z "$INPUT_DIR" ]]; then
    echo "Missing required option: --input-dir" >&2
    usage
    exit 64
fi

if [[ ! -d "$INPUT_DIR" ]]; then
    echo "Input directory does not exist: $INPUT_DIR" >&2
    exit 66
fi

mkdir -p "$OUTPUT_DIR"

CMD=(
    swift run lanread-batch generate
    --input-dir "$INPUT_DIR"
    --output "$OUTPUT_DIR"
    --highlights "$HIGHLIGHTS"
    --language "$LANGUAGE"
    --style "$STYLE"
    --profile-name "$PROFILE_NAME"
    --overwrite-policy "$OVERWRITE_POLICY"
)

if [[ -n "$PROVIDER_CONFIG" ]]; then
    CMD+=(--provider-config "$PROVIDER_CONFIG")
fi

if [[ -n "$PROFILE_AVATAR" ]]; then
    CMD+=(--profile-avatar "$PROFILE_AVATAR")
fi

if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
    CMD+=("${EXTRA_ARGS[@]}")
fi

echo "Running command:"
printf '  %q' "${CMD[@]}"
echo
echo

"${CMD[@]}"

SUMMARY_FILE="$OUTPUT_DIR/batch.summary.json"
if [[ -f "$SUMMARY_FILE" ]]; then
    echo
    echo "Batch summary written to: $SUMMARY_FILE"
fi
