#!/bin/bash

################################################################################
# LanRead - 模拟器管理脚本
# 用途：管理 iOS 模拟器（列出、启动、停止、重置）
# 使用方法：./scripts/simulator.sh [list|start|stop|reset|logs]
################################################################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

PROJECT_NAME="LanRead"
BUNDLE_ID="top.islareader.lanread"

# 显示帮助信息
show_help() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  📱 iOS 模拟器管理工具${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "用法: $0 <command> [options]"
    echo ""
    echo "命令:"
    echo "  list              列出所有可用的模拟器"
    echo "  start [name]      启动指定的模拟器（默认：iPhone 15）"
    echo "  stop [name]       关闭指定的模拟器（默认：关闭所有）"
    echo "  reset [name]      重置模拟器数据"
    echo "  logs              查看应用日志"
    echo "  status            查看应用安装状态"
    echo "  uninstall         卸载应用"
    echo "  screenshot        截图并保存"
    echo "  record [duration] 录制模拟器视频（默认30秒）"
    echo ""
    echo "示例:"
    echo "  $0 list"
    echo "  $0 start \"iPhone 15 Pro\""
    echo "  $0 stop"
    echo "  $0 reset \"iPhone 15\""
    echo "  $0 logs"
    echo "  $0 screenshot"
    echo "  $0 record 60"
    echo ""
}

# 列出所有模拟器
list_simulators() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}📱 可用的 iOS 模拟器:${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    echo -e "${GREEN}iPhone 系列:${NC}"
    xcrun simctl list devices available | grep "iPhone" | sed 's/^/  /'
    echo ""
    
    echo -e "${GREEN}iPad 系列:${NC}"
    xcrun simctl list devices available | grep "iPad" | sed 's/^/  /'
    echo ""
    
    echo -e "${YELLOW}正在运行的模拟器:${NC}"
    RUNNING=$(xcrun simctl list devices | grep "Booted" || echo "  无")
    if [ "$RUNNING" == "  无" ]; then
        echo "  无"
    else
        echo "$RUNNING" | sed 's/^/  /'
    fi
    echo ""
}

# 启动模拟器
start_simulator() {
    local SIMULATOR_NAME="${1:-iPhone 15}"
    
    echo -e "${YELLOW}🚀 启动模拟器: $SIMULATOR_NAME${NC}"
    
    SIMULATOR_UDID=$(xcrun simctl list devices available | grep "$SIMULATOR_NAME" | head -1 | grep -o -E '\([A-F0-9-]+\)' | tr -d '()')
    
    if [ -z "$SIMULATOR_UDID" ]; then
        echo -e "${RED}❌ 未找到模拟器: $SIMULATOR_NAME${NC}"
        echo ""
        echo "可用的模拟器:"
        list_simulators
        exit 1
    fi
    
    SIMULATOR_STATE=$(xcrun simctl list devices | grep "$SIMULATOR_UDID" | grep -o -E '\((Booted|Shutdown)\)' | tr -d '()')
    
    if [ "$SIMULATOR_STATE" == "Booted" ]; then
        echo -e "${GREEN}✅ 模拟器已在运行中${NC}"
    else
        xcrun simctl boot "$SIMULATOR_UDID"
        open -a Simulator
        echo -e "${GREEN}✅ 模拟器已启动${NC}"
    fi
    
    echo -e "${BLUE}UDID: ${NC}$SIMULATOR_UDID"
}

# 停止模拟器
stop_simulator() {
    local SIMULATOR_NAME="$1"
    
    if [ -z "$SIMULATOR_NAME" ]; then
        echo -e "${YELLOW}🛑 关闭所有模拟器...${NC}"
        xcrun simctl shutdown all
        killall Simulator 2>/dev/null || true
        echo -e "${GREEN}✅ 所有模拟器已关闭${NC}"
    else
        echo -e "${YELLOW}🛑 关闭模拟器: $SIMULATOR_NAME${NC}"
        SIMULATOR_UDID=$(xcrun simctl list devices | grep "$SIMULATOR_NAME" | head -1 | grep -o -E '\([A-F0-9-]+\)' | tr -d '()')
        
        if [ -z "$SIMULATOR_UDID" ]; then
            echo -e "${RED}❌ 未找到模拟器: $SIMULATOR_NAME${NC}"
            exit 1
        fi
        
        xcrun simctl shutdown "$SIMULATOR_UDID"
        echo -e "${GREEN}✅ 模拟器已关闭${NC}"
    fi
}

# 重置模拟器
reset_simulator() {
    local SIMULATOR_NAME="${1:-iPhone 15}"
    
    echo -e "${YELLOW}⚠️  警告: 即将重置模拟器数据！${NC}"
    echo -e "${YELLOW}模拟器: $SIMULATOR_NAME${NC}"
    echo ""
    read -p "确认重置？(y/N) " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}已取消${NC}"
        exit 0
    fi
    
    SIMULATOR_UDID=$(xcrun simctl list devices available | grep "$SIMULATOR_NAME" | head -1 | grep -o -E '\([A-F0-9-]+\)' | tr -d '()')
    
    if [ -z "$SIMULATOR_UDID" ]; then
        echo -e "${RED}❌ 未找到模拟器: $SIMULATOR_NAME${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}🔄 重置中...${NC}"
    xcrun simctl shutdown "$SIMULATOR_UDID" 2>/dev/null || true
    xcrun simctl erase "$SIMULATOR_UDID"
    echo -e "${GREEN}✅ 模拟器已重置${NC}"
}

# 查看应用日志
view_logs() {
    echo -e "${CYAN}📋 查看应用日志（按 Ctrl+C 退出）${NC}"
    echo ""
    
    # 获取正在运行的模拟器
    BOOTED_UDID=$(xcrun simctl list devices | grep "Booted" | head -1 | grep -o -E '\([A-F0-9-]+\)' | tr -d '()')
    
    if [ -z "$BOOTED_UDID" ]; then
        echo -e "${RED}❌ 没有正在运行的模拟器${NC}"
        echo "请先启动模拟器: ./scripts/simulator.sh start"
        exit 1
    fi
    
    xcrun simctl spawn "$BOOTED_UDID" log stream \
        --predicate "processImagePath CONTAINS \"$PROJECT_NAME\"" \
        --style compact \
        --color always
}

# 查看应用状态
check_status() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}📊 应用状态${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # 获取正在运行的模拟器
    BOOTED_UDID=$(xcrun simctl list devices | grep "Booted" | head -1 | grep -o -E '\([A-F0-9-]+\)' | tr -d '()')
    
    if [ -z "$BOOTED_UDID" ]; then
        echo -e "${RED}❌ 没有正在运行的模拟器${NC}"
        return
    fi
    
    BOOTED_NAME=$(xcrun simctl list devices | grep "$BOOTED_UDID" | sed 's/(.*//' | xargs)
    echo -e "${GREEN}运行中的模拟器: ${NC}$BOOTED_NAME"
    echo -e "${BLUE}UDID: ${NC}$BOOTED_UDID"
    echo ""
    
    # 检查应用是否已安装
    if xcrun simctl get_app_container "$BOOTED_UDID" "$BUNDLE_ID" &>/dev/null; then
        echo -e "${GREEN}✅ 应用已安装${NC}"
        echo -e "${BLUE}Bundle ID: ${NC}$BUNDLE_ID"
        
        # 获取应用容器路径
        APP_CONTAINER=$(xcrun simctl get_app_container "$BOOTED_UDID" "$BUNDLE_ID" 2>/dev/null)
        echo -e "${BLUE}容器路径: ${NC}$APP_CONTAINER"
    else
        echo -e "${YELLOW}⚠️  应用未安装${NC}"
    fi
    echo ""
}

# 卸载应用
uninstall_app() {
    echo -e "${YELLOW}🗑️  卸载应用...${NC}"
    
    BOOTED_UDID=$(xcrun simctl list devices | grep "Booted" | head -1 | grep -o -E '\([A-F0-9-]+\)' | tr -d '()')
    
    if [ -z "$BOOTED_UDID" ]; then
        echo -e "${RED}❌ 没有正在运行的模拟器${NC}"
        exit 1
    fi
    
    xcrun simctl uninstall "$BOOTED_UDID" "$BUNDLE_ID" 2>/dev/null || true
    echo -e "${GREEN}✅ 应用已卸载${NC}"
}

# 截图
take_screenshot() {
    echo -e "${YELLOW}📸 截图中...${NC}"
    
    BOOTED_UDID=$(xcrun simctl list devices | grep "Booted" | head -1 | grep -o -E '\([A-F0-9-]+\)' | tr -d '()')
    
    if [ -z "$BOOTED_UDID" ]; then
        echo -e "${RED}❌ 没有正在运行的模拟器${NC}"
        exit 1
    fi
    
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    SCREENSHOT_FILE="screenshot_$TIMESTAMP.png"
    
    xcrun simctl io "$BOOTED_UDID" screenshot "$SCREENSHOT_FILE"
    echo -e "${GREEN}✅ 截图已保存: ${NC}$SCREENSHOT_FILE"
    
    # 在 macOS 上打开图片
    open "$SCREENSHOT_FILE"
}

# 录制视频
record_video() {
    local DURATION="${1:-30}"
    
    echo -e "${YELLOW}🎥 开始录制视频（${DURATION}秒）...${NC}"
    
    BOOTED_UDID=$(xcrun simctl list devices | grep "Booted" | head -1 | grep -o -E '\([A-F0-9-]+\)' | tr -d '()')
    
    if [ -z "$BOOTED_UDID" ]; then
        echo -e "${RED}❌ 没有正在运行的模拟器${NC}"
        exit 1
    fi
    
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    VIDEO_FILE="recording_$TIMESTAMP.mov"
    
    echo -e "${CYAN}录制中...（${DURATION}秒后自动停止，或按 Ctrl+C 提前停止）${NC}"
    
    # 使用 timeout 命令限制录制时间
    timeout "$DURATION" xcrun simctl io "$BOOTED_UDID" recordVideo "$VIDEO_FILE" || true
    
    echo ""
    echo -e "${GREEN}✅ 视频已保存: ${NC}$VIDEO_FILE"
    
    # 在 macOS 上打开视频
    open "$VIDEO_FILE"
}

# 主程序
case "${1:-help}" in
    list)
        list_simulators
        ;;
    start)
        start_simulator "$2"
        ;;
    stop)
        stop_simulator "$2"
        ;;
    reset)
        reset_simulator "$2"
        ;;
    logs)
        view_logs
        ;;
    status)
        check_status
        ;;
    uninstall)
        uninstall_app
        ;;
    screenshot)
        take_screenshot
        ;;
    record)
        record_video "$2"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}❌ 未知命令: $1${NC}"
        echo ""
        show_help
        exit 1
        ;;
esac
