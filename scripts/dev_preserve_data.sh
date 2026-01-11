#!/bin/bash

################################################################################
# LanRead - 开发脚本（保留模拟器数据）
# 用途：编译并运行，但跳过卸载以保留上一次的模拟器数据（如已导入书籍）
# 使用方法：./scripts/dev_preserve_data.sh [simulator_name]
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
echo -e "${MAGENTA}║   🚀 LanRead 开发启动（保留模拟器数据）   ║${NC}"
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

# 步骤 2: 运行（跳过卸载，保留数据）
echo -e "${BLUE}📍 步骤 2/2: 启动模拟器并运行应用（保留数据）${NC}"
echo ""

# 传递模拟器名称参数（如果有）
if [ -n "$1" ]; then
    PRESERVE_SIM_DATA=1 "$SCRIPT_DIR/run.sh" "$1"
else
    PRESERVE_SIM_DATA=1 "$SCRIPT_DIR/run.sh"
fi

