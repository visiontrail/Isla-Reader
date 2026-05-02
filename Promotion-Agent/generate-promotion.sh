#!/usr/bin/env bash
################################################################################
# LanRead - Promotion 高亮分享图生成工具
#
# AI Agent 调用示例（只需传 epub 路径）:
#   ./Promotion-Agent/generate-promotion.sh --epub "/path/to/book.epub"
#
# 完整参数示例:
#   ./Promotion-Agent/generate-promotion.sh \
#     --epub "/path/to/book.epub" \
#     --output "Promotion/20260502-bookname" \
#     --highlights 30 \
#     --language en \
#     --style white \
#     --profile-name "LeoGuo" \
#     --profile-avatar "/Users/guoliang/Downloads/Flamingo.png" \
#     --timezone "America/New_York"
################################################################################

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

# ── 默认值（与你日常使用的参数一致）──────────────────────────────────────────
DEFAULT_HIGHLIGHTS=30
DEFAULT_LANGUAGE="en"
DEFAULT_STYLE="white"
DEFAULT_PROFILE_NAME="LeoGuo"
DEFAULT_PROFILE_AVATAR="/Users/guoliang/Downloads/Flamingo.png"
DEFAULT_TIMEZONE="America/New_York"
DEFAULT_PROVIDER_CONFIG="$PROJECT_DIR/Batch/ai.json"

# ── 参数变量 ──────────────────────────────────────────────────────────────────
EPUB_PATH=""
OUTPUT_PATH=""
HIGHLIGHTS="$DEFAULT_HIGHLIGHTS"
LANGUAGE="$DEFAULT_LANGUAGE"
STYLE="$DEFAULT_STYLE"
PROFILE_NAME="$DEFAULT_PROFILE_NAME"
PROFILE_AVATAR="$DEFAULT_PROFILE_AVATAR"
TIMEZONE="$DEFAULT_TIMEZONE"
PROVIDER_CONFIG="$DEFAULT_PROVIDER_CONFIG"

usage() {
    cat <<EOF
Usage:
  ./Promotion-Agent/generate-promotion.sh --epub <path> [options]

Required:
  --epub <path>              EPUB 文件路径（绝对路径或相对于项目根目录）

Optional:
  --output <path>            输出目录。默认: Promotion/<YYYYMMDD>-<book-slug>
  --highlights <n>           目标高亮数量。默认: $DEFAULT_HIGHLIGHTS
  --language <code>          输出语言（如 en / zh-Hans / ja）。默认: $DEFAULT_LANGUAGE
  --style <value>            分享卡样式: none | white | black。默认: $DEFAULT_STYLE
  --profile-name <name>      分享卡署名。默认: $DEFAULT_PROFILE_NAME
  --profile-avatar <path>    头像图片路径。默认: $DEFAULT_PROFILE_AVATAR
  --timezone <tz>            时区（如 America/New_York）。默认: $DEFAULT_TIMEZONE
  --provider-config <path>   AI provider 配置 JSON。默认: Batch/ai.json
  -h, --help                 显示帮助

Output:
  生成结果写入 <output>/，包含:
    images/*.png           高亮分享图
    manifest.json          完整产物清单
    selected.stage2.json   最终入选高亮列表
    logs/                  运行日志与指标
EOF
}

# ── 解析参数 ──────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --epub)             EPUB_PATH="$2";       shift 2 ;;
        --output)           OUTPUT_PATH="$2";     shift 2 ;;
        --highlights)       HIGHLIGHTS="$2";      shift 2 ;;
        --language)         LANGUAGE="$2";        shift 2 ;;
        --style)            STYLE="$2";           shift 2 ;;
        --profile-name)     PROFILE_NAME="$2";    shift 2 ;;
        --profile-avatar)   PROFILE_AVATAR="$2";  shift 2 ;;
        --timezone)         TIMEZONE="$2";        shift 2 ;;
        --provider-config)  PROVIDER_CONFIG="$2"; shift 2 ;;
        -h|--help)          usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 64 ;;
    esac
done

# ── 必要参数检查 ───────────────────────────────────────────────────────────────
if [[ -z "$EPUB_PATH" ]]; then
    echo "Error: --epub is required." >&2
    usage >&2
    exit 64
fi

# 如果传入的是相对路径，基于项目根目录补全
if [[ "$EPUB_PATH" != /* ]]; then
    EPUB_PATH="$PROJECT_DIR/$EPUB_PATH"
fi

if [[ ! -f "$EPUB_PATH" ]]; then
    echo "Error: EPUB file not found: $EPUB_PATH" >&2
    exit 1
fi

# ── 自动生成输出目录名 ─────────────────────────────────────────────────────────
if [[ -z "$OUTPUT_PATH" ]]; then
    DATE_SLUG="$(date '+%Y%m%d')"
    # 从文件名派生 slug：去掉扩展名，空格/特殊字符替换为连字符，转小写
    BOOK_SLUG="$(basename "$EPUB_PATH" .epub | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')"
    OUTPUT_PATH="$PROJECT_DIR/Promotion/${DATE_SLUG}-${BOOK_SLUG}"
fi

# 相对路径同样补全
if [[ "$OUTPUT_PATH" != /* ]]; then
    OUTPUT_PATH="$PROJECT_DIR/$OUTPUT_PATH"
fi

# ── 执行 ───────────────────────────────────────────────────────────────────────
cd "$PROJECT_DIR"

echo "──────────────────────────────────────────────"
echo "LanRead Promotion Generator"
echo "  EPUB    : $EPUB_PATH"
echo "  Output  : $OUTPUT_PATH"
echo "  Language: $LANGUAGE  Highlights: $HIGHLIGHTS  Style: $STYLE"
echo "  Profile : $PROFILE_NAME  Timezone: $TIMEZONE"
echo "──────────────────────────────────────────────"

ARGS=(
    generate
    --epub        "$EPUB_PATH"
    --output      "$OUTPUT_PATH"
    --highlights  "$HIGHLIGHTS"
    --language    "$LANGUAGE"
    --style       "$STYLE"
    --profile-name    "$PROFILE_NAME"
    --timezone    "$TIMEZONE"
)

if [[ -n "$PROVIDER_CONFIG" && -f "$PROVIDER_CONFIG" ]]; then
    ARGS+=(--provider-config "$PROVIDER_CONFIG")
fi

if [[ -n "$PROFILE_AVATAR" && -f "$PROFILE_AVATAR" ]]; then
    ARGS+=(--profile-avatar "$PROFILE_AVATAR")
fi

swift run lanread-batch "${ARGS[@]}"

echo ""
echo "Done. Output: $OUTPUT_PATH"
