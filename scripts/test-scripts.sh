#!/bin/bash

################################################################################
# Isla Reader - 脚本测试工具
# 用途：验证所有脚本是否正常工作
################################################################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 获取脚本目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR/.."

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  🧪 脚本环境测试${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

TESTS_PASSED=0
TESTS_FAILED=0

# 测试函数
test_command() {
    local TEST_NAME="$1"
    local COMMAND="$2"
    
    echo -e "${YELLOW}测试: ${NC}$TEST_NAME"
    
    if eval "$COMMAND" > /dev/null 2>&1; then
        echo -e "${GREEN}  ✅ 通过${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}  ❌ 失败${NC}"
        ((TESTS_FAILED++))
    fi
    echo ""
}

# 1. 检查必要的命令
echo -e "${BLUE}📋 检查系统依赖${NC}"
echo ""

test_command "xcodebuild 命令" "command -v xcodebuild"
test_command "xcrun 命令" "command -v xcrun"
test_command "xcode-select 安装" "xcode-select -p"

# 2. 检查 Xcode 版本
echo -e "${BLUE}📋 Xcode 信息${NC}"
echo ""
if command -v xcodebuild &> /dev/null; then
    XCODE_VERSION=$(xcodebuild -version | head -1)
    echo -e "${GREEN}  $XCODE_VERSION${NC}"
    echo ""
fi

# 3. 检查脚本文件
echo -e "${BLUE}📋 检查脚本文件${NC}"
echo ""

SCRIPTS=("build.sh" "run.sh" "dev.sh" "simulator.sh")

for script in "${SCRIPTS[@]}"; do
    if [ -f "scripts/$script" ]; then
        if [ -x "scripts/$script" ]; then
            echo -e "${GREEN}  ✅ $script (可执行)${NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${YELLOW}  ⚠️  $script (不可执行)${NC}"
            echo -e "${YELLOW}     运行: chmod +x scripts/$script${NC}"
            ((TESTS_FAILED++))
        fi
    else
        echo -e "${RED}  ❌ $script (不存在)${NC}"
        ((TESTS_FAILED++))
    fi
done
echo ""

# 4. 检查项目文件
echo -e "${BLUE}📋 检查项目文件${NC}"
echo ""

PROJECT_FILES=("Isla Reader.xcodeproj" "Isla Reader/Info.plist")

for file in "${PROJECT_FILES[@]}"; do
    if [ -e "$file" ]; then
        echo -e "${GREEN}  ✅ $file${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}  ❌ $file${NC}"
        ((TESTS_FAILED++))
    fi
done
echo ""

# 5. 检查模拟器
echo -e "${BLUE}📋 检查可用模拟器${NC}"
echo ""

SIMULATOR_COUNT=$(xcrun simctl list devices available | grep "iPhone" | wc -l | xargs)

if [ "$SIMULATOR_COUNT" -gt 0 ]; then
    echo -e "${GREEN}  ✅ 找到 $SIMULATOR_COUNT 个 iPhone 模拟器${NC}"
    ((TESTS_PASSED++))
    
    # 显示前5个
    echo ""
    echo -e "${BLUE}  可用模拟器示例:${NC}"
    xcrun simctl list devices available | grep "iPhone" | head -5 | sed 's/^/    /'
else
    echo -e "${RED}  ❌ 未找到可用的模拟器${NC}"
    ((TESTS_FAILED++))
fi
echo ""

# 6. 检查是否有正在运行的模拟器
RUNNING_SIMS=$(xcrun simctl list devices | grep "Booted" | wc -l | xargs)
if [ "$RUNNING_SIMS" -gt 0 ]; then
    echo -e "${GREEN}  ℹ️  当前有 $RUNNING_SIMS 个模拟器正在运行${NC}"
else
    echo -e "${BLUE}  ℹ️  当前没有运行中的模拟器${NC}"
fi
echo ""

# 7. 检查编译输出目录
echo -e "${BLUE}📋 检查构建目录${NC}"
echo ""

if [ -d "build" ]; then
    BUILD_SIZE=$(du -sh build 2>/dev/null | cut -f1)
    echo -e "${GREEN}  ✅ build 目录存在 (大小: $BUILD_SIZE)${NC}"
    ((TESTS_PASSED++))
    
    APP_PATH="build/Build/Products/Debug-iphonesimulator/Isla Reader.app"
    if [ -d "$APP_PATH" ]; then
        echo -e "${GREEN}  ✅ 已编译的应用存在${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${YELLOW}  ⚠️  应用未编译，运行 ./scripts/build.sh 编译${NC}"
    fi
else
    echo -e "${YELLOW}  ⚠️  build 目录不存在（首次运行正常）${NC}"
fi
echo ""

# 8. 测试脚本帮助信息
echo -e "${BLUE}📋 测试脚本帮助信息${NC}"
echo ""

if ./scripts/simulator.sh help > /dev/null 2>&1; then
    echo -e "${GREEN}  ✅ simulator.sh help${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${RED}  ❌ simulator.sh help${NC}"
    ((TESTS_FAILED++))
fi
echo ""

# 总结
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  📊 测试结果${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${GREEN}  通过: $TESTS_PASSED${NC}"
echo -e "${RED}  失败: $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 所有测试通过！环境配置正确。${NC}"
    echo ""
    echo -e "${BLUE}你可以开始使用以下命令:${NC}"
    echo "  ./scripts/build.sh       # 编译项目"
    echo "  ./scripts/run.sh         # 运行应用"
    echo "  ./scripts/dev.sh         # 一键编译+运行（推荐）"
    echo "  ./scripts/simulator.sh   # 管理模拟器"
    echo ""
    exit 0
else
    echo -e "${YELLOW}⚠️  有 $TESTS_FAILED 个测试失败，请检查上述错误。${NC}"
    echo ""
    exit 1
fi

