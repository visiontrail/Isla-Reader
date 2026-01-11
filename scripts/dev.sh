#!/bin/bash

################################################################################
# LanRead - 开发脚本（一键编译并运行）
# 用途：自动执行编译和运行流程
# 使用方法：./scripts/dev.sh [simulator_name]
################################################################################

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# 获取脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo -e "${MAGENTA}╔════════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║      🚀 LanRead 开发环境快速启动         ║${NC}"
echo -e "${MAGENTA}╚════════════════════════════════════════════════╝${NC}"
echo ""

# 步骤 1: 编译
echo -e "${BLUE}📍 步骤 1/2: 编译项目${NC}"
echo ""
if "$SCRIPT_DIR/build.sh" debug; then
    echo ""
    echo -e "${GREEN}✅ 编译完成${NC}"
else
    echo -e "${RED}❌ 编译失败，终止运行${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 步骤 2: 运行
echo -e "${BLUE}📍 步骤 2/2: 启动模拟器并运行应用${NC}"
echo ""

# 传递模拟器名称参数（如果有）
if [ -n "$1" ]; then
    "$SCRIPT_DIR/run.sh" "$1"
else
    "$SCRIPT_DIR/run.sh"
fi

