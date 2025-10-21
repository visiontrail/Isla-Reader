#!/bin/bash

################################################################################
# Isla Reader - 编译脚本
# 用途：清理并编译 iOS 项目
# 使用方法：./scripts/build.sh [clean|debug|release]
################################################################################

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 项目配置
PROJECT_NAME="Isla Reader"
PROJECT_FILE="Isla Reader.xcodeproj"
SCHEME="Isla Reader"
BUILD_DIR="./build"
CONFIGURATION="Debug"  # 默认为 Debug

# 获取脚本所在目录的父目录（项目根目录）
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

# 切换到项目目录
cd "$PROJECT_DIR"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  🚀 Isla Reader 编译脚本${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 处理命令行参数
if [ "$1" == "clean" ]; then
    echo -e "${YELLOW}🧹 执行清理编译...${NC}"
    CLEAN=true
elif [ "$1" == "release" ]; then
    echo -e "${YELLOW}📦 编译 Release 版本...${NC}"
    CONFIGURATION="Release"
elif [ "$1" == "debug" ] || [ -z "$1" ]; then
    echo -e "${YELLOW}🔧 编译 Debug 版本...${NC}"
    CONFIGURATION="Debug"
else
    echo -e "${RED}❌ 未知参数: $1${NC}"
    echo "用法: $0 [clean|debug|release]"
    exit 1
fi

# 检查是否安装了 Xcode
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}❌ 错误: 未找到 xcodebuild 命令${NC}"
    echo "请安装 Xcode Command Line Tools:"
    echo "  xcode-select --install"
    exit 1
fi

# 显示 Xcode 版本
echo -e "${BLUE}📱 Xcode 版本信息:${NC}"
xcodebuild -version
echo ""

# 显示可用的模拟器
echo -e "${BLUE}📱 可用的 iOS 模拟器:${NC}"
xcrun simctl list devices available | grep iPhone | head -5
echo ""

# 清理旧的构建
if [ "$CLEAN" == true ]; then
    echo -e "${YELLOW}🧹 清理旧的构建文件...${NC}"
    xcodebuild clean \
        -project "$PROJECT_FILE" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" 2>&1 | grep -E "CLEAN (SUCCEEDED|FAILED)|error:" || true
    
    if [ -d "$BUILD_DIR" ]; then
        echo -e "${YELLOW}🧹 删除 build 目录...${NC}"
        rm -rf "$BUILD_DIR"
    fi
    echo ""
fi

# 开始编译
echo -e "${GREEN}⚙️  开始编译项目...${NC}"
echo -e "${BLUE}配置: ${NC}$CONFIGURATION"
echo -e "${BLUE}目标: ${NC}iOS Simulator"
echo ""

# 编译项目
BUILD_START=$(date +%s)

xcodebuild build \
    -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'platform=iOS Simulator,name=iPhone 15' \
    -derivedDataPath "$BUILD_DIR" \
    -quiet \
    | tee build.log \
    | grep -E "Build (succeeded|failed)|error:|warning:" || true

BUILD_RESULT=${PIPESTATUS[0]}
BUILD_END=$(date +%s)
BUILD_TIME=$((BUILD_END - BUILD_START))

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ $BUILD_RESULT -eq 0 ]; then
    echo -e "${GREEN}✅ 编译成功！${NC}"
    echo -e "${GREEN}⏱  编译耗时: ${BUILD_TIME}秒${NC}"
    echo ""
    
    # 显示生成的 .app 文件位置
    APP_PATH="$BUILD_DIR/Build/Products/$CONFIGURATION-iphonesimulator/$PROJECT_NAME.app"
    if [ -d "$APP_PATH" ]; then
        echo -e "${BLUE}📦 应用路径:${NC}"
        echo "   $APP_PATH"
        echo ""
        echo -e "${GREEN}🎉 现在可以运行 ./scripts/run.sh 来启动应用${NC}"
    fi
else
    echo -e "${RED}❌ 编译失败！${NC}"
    echo -e "${RED}⏱  失败耗时: ${BUILD_TIME}秒${NC}"
    echo ""
    echo -e "${YELLOW}📋 查看详细错误日志:${NC}"
    echo "   cat build.log | grep error"
    exit 1
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

