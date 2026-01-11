#!/bin/bash

################################################################################
# LanRead - 运行脚本
# 用途：启动 iOS 模拟器并运行应用，同时输出控制台日志
# 使用方法：./scripts/run.sh [simulator_name]
# 示例：./scripts/run.sh "iPhone 15 Pro"
################################################################################

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 项目配置
PROJECT_NAME="LanRead"
BUNDLE_ID="LeoGuo.Isla-Reader-Local"
BUILD_DIR="./build"
CONFIGURATION="Debug"
DEFAULT_SIMULATOR="iPhone 16"
PRESERVE_SIM_DATA="${PRESERVE_SIM_DATA:-0}"

# 获取脚本所在目录的父目录（项目根目录）
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

# 切换到项目目录
cd "$PROJECT_DIR"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  🚀 LanRead 运行脚本${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 检查是否安装了必要的工具
if ! command -v xcrun &> /dev/null; then
    echo -e "${RED}❌ 错误: 未找到 xcrun 命令${NC}"
    echo "请安装 Xcode Command Line Tools:"
    echo "  xcode-select --install"
    exit 1
fi

# 获取模拟器名称（从参数或使用默认值）
SIMULATOR_NAME="${1:-$DEFAULT_SIMULATOR}"

echo -e "${YELLOW}📱 目标模拟器: ${NC}$SIMULATOR_NAME"
if [ "$PRESERVE_SIM_DATA" = "1" ]; then
    echo -e "${YELLOW}🔒 数据策略: 保留上次模拟器数据，跳过卸载${NC}"
else
    echo -e "${YELLOW}🗑️  数据策略: 卸载后全新安装（会清空模拟器数据）${NC}"
fi
echo ""

# 查找模拟器 UDID
echo -e "${BLUE}🔍 查找模拟器...${NC}"
SIMULATOR_UDID=$(xcrun simctl list devices available | grep "$SIMULATOR_NAME" | grep -v "unavailable" | head -1 | grep -o -E '\([A-F0-9-]+\)' | tr -d '()')

if [ -z "$SIMULATOR_UDID" ]; then
    echo -e "${RED}❌ 错误: 未找到模拟器 '$SIMULATOR_NAME'${NC}"
    echo ""
    echo -e "${YELLOW}可用的模拟器列表:${NC}"
    xcrun simctl list devices available | grep "iPhone" | sed 's/^/  /'
    exit 1
fi

echo -e "${GREEN}✅ 找到模拟器: $SIMULATOR_NAME${NC}"
echo -e "${BLUE}   UDID: ${NC}$SIMULATOR_UDID"
echo ""

# 检查应用是否已编译
APP_PATH="$BUILD_DIR/Build/Products/$CONFIGURATION-iphonesimulator/$PROJECT_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}❌ 错误: 未找到编译好的应用${NC}"
    echo -e "${YELLOW}请先运行编译脚本:${NC}"
    echo "  ./scripts/build.sh"
    exit 1
fi

echo -e "${GREEN}✅ 找到应用: ${NC}$APP_PATH"
echo ""

# 检查模拟器状态
SIMULATOR_STATE=$(xcrun simctl list devices | grep "$SIMULATOR_UDID" | grep -o -E '\((Booted|Shutdown)\)' | tr -d '()')

if [ "$SIMULATOR_STATE" != "Booted" ]; then
    echo -e "${YELLOW}🔄 启动模拟器...${NC}"
    xcrun simctl boot "$SIMULATOR_UDID"
    
    # 打开模拟器窗口
    open -a Simulator
    
    # 等待模拟器完全启动
    echo -e "${YELLOW}⏳ 等待模拟器启动...${NC}"
    sleep 3
    
    echo -e "${GREEN}✅ 模拟器已启动${NC}"
else
    echo -e "${GREEN}✅ 模拟器已在运行中${NC}"
fi
echo ""

# 安装应用
echo -e "${YELLOW}📦 安装应用到模拟器...${NC}"
if [ "$PRESERVE_SIM_DATA" = "1" ]; then
    echo -e "${YELLOW}🔄 跳过卸载，尝试直接覆盖安装以保留数据${NC}"
else
    echo -e "${YELLOW}🗑️  卸载旧版本应用...${NC}"
    xcrun simctl uninstall "$SIMULATOR_UDID" "$BUNDLE_ID" 2>/dev/null || true
fi
xcrun simctl install "$SIMULATOR_UDID" "$APP_PATH"
echo -e "${GREEN}✅ 应用安装成功${NC}"
echo ""

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}📋 应用控制台日志输出（按 Ctrl+C 退出）:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 启动应用并同时捕获标准输出和标准错误
# --console 选项会将应用的 stdout/stderr 输出到当前终端
# --console-pty 选项提供伪终端支持，确保实时输出
echo -e "${YELLOW}🚀 启动应用并开始日志跟踪...${NC}"
xcrun simctl launch --console-pty "$SIMULATOR_UDID" "$BUNDLE_ID"
