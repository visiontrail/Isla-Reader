# 📜 LanRead 命令行脚本使用指南

本目录包含用于编译、运行和开发 LanRead iOS 应用的自动化脚本。

## 📋 脚本列表

### 1. `build.sh` - 编译脚本
编译 iOS 项目，生成可在模拟器上运行的应用。

**使用方法：**
```bash
# 基础编译（Debug 模式）
./scripts/build.sh

# Debug 模式编译
./scripts/build.sh debug

# Release 模式编译
./scripts/build.sh release

# 清理后编译
./scripts/build.sh clean
```

**功能特性：**
- ✅ 自动检测 Xcode 环境
- ✅ 显示编译进度和耗时
- ✅ 支持 Debug 和 Release 配置
- ✅ 生成详细的编译日志（build.log）
- ✅ 编译成功后显示 .app 文件路径

**输出文件位置：**
```
./build/Build/Products/Debug-iphonesimulator/LanRead.app
```

---

### 2. `run.sh` - 运行脚本
启动 iOS 模拟器，安装并运行应用，实时输出控制台日志。

**使用方法：**
```bash
# 使用默认模拟器（iPhone 16）
./scripts/run.sh

# 指定模拟器
./scripts/run.sh "iPhone 16 Pro"
./scripts/run.sh "iPhone 15 Pro"
./scripts/run.sh "iPad Pro (12.9-inch)"
```

**功能特性：**
- ✅ 自动启动模拟器（如果未运行）
- ✅ 自动卸载旧版本应用
- ✅ 安装并启动新版本
- ✅ **实时输出应用控制台日志到当前 Shell**
- ✅ 彩色日志输出，易于阅读
- ✅ 按 Ctrl+C 退出日志监控

**查看可用模拟器：**
```bash
xcrun simctl list devices available | grep iPhone
```

---

### 3. `dev.sh` - 开发脚本（一键编译运行）
结合编译和运行流程，适合快速开发迭代。

**使用方法：**
```bash
# 使用默认模拟器
./scripts/dev.sh

# 指定模拟器
./scripts/dev.sh "iPhone 16 Pro"
```

**执行流程：**
1. 📦 编译项目（Debug 模式）
2. 🚀 启动模拟器
3. 📱 安装应用
4. 🏃 运行应用
5. 📋 实时显示日志

---

## 🚀 快速开始

### 第一次使用

1. **确保已安装 Xcode：**
   ```bash
   xcode-select --install
   xcodebuild -version
   ```

2. **编译项目：**
   ```bash
   cd "/Users/guoliang/Desktop/workspace/code/SelfProject/IslaProject/LanRead-ios/Isla Reader"
   ./scripts/build.sh
   ```

3. **运行应用：**
   ```bash
   ./scripts/run.sh
   ```

### 日常开发流程

**方案一：分步执行**
```bash
# 1. 修改代码
# 2. 编译
./scripts/build.sh

# 3. 运行
./scripts/run.sh
```

**方案二：一键运行**
```bash
# 修改代码后直接运行
./scripts/dev.sh
```

---

## 📊 控制台日志输出

### 日志特性

运行 `run.sh` 或 `dev.sh` 后，控制台会实时显示应用的日志输出，包括：

- 🔵 **系统日志**：iOS 系统消息
- 🟢 **应用日志**：您的 print() 和 NSLog() 输出
- 🟡 **警告信息**：性能和内存警告
- 🔴 **错误信息**：崩溃和异常

### 在代码中添加日志

```swift
// 简单日志
print("📚 加载书籍: \(bookTitle)")

// 使用 OSLog（推荐）
import os

let logger = Logger(subsystem: "LeoGuo.Isla-Reader", category: "BookManager")
logger.info("📚 加载书籍: \(bookTitle)")
logger.error("❌ 加载失败: \(error.localizedDescription)")
```

### 日志过滤

如果日志太多，可以使用 grep 过滤：

```bash
# 只显示包含特定关键字的日志
./scripts/run.sh | grep "BookManager"

# 只显示错误
./scripts/run.sh | grep -i error

# 排除某些日志
./scripts/run.sh | grep -v "UIKit"
```

---

## 🛠️ 高级用法

### 指定不同的模拟器

```bash
# iPhone 系列（推荐使用 iOS 18.2+ 的模拟器）
./scripts/run.sh "iPhone 16 Pro Max"
./scripts/run.sh "iPhone 16 Pro"
./scripts/run.sh "iPhone 16"

# iPad 系列（需要 iOS 18.2+ 版本）
./scripts/run.sh "iPad Pro (12.9-inch)"
./scripts/run.sh "iPad Air 11-inch (M3)"
```

### 编译特定配置

```bash
# Release 编译（优化性能）
./scripts/build.sh release

# 清理所有缓存后编译
./scripts/build.sh clean
rm -rf "./build"
./scripts/build.sh debug
```

### 后台运行（不查看日志）

如果你只想启动应用而不需要查看日志：

```bash
# 修改 run.sh 最后一行，注释掉日志输出
# 或者使用 nohup
nohup ./scripts/run.sh > /dev/null 2>&1 &
```

---

## 🐛 故障排查

> 💡 **提示**: 更多详细的故障排查信息，请查看 [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)

### 问题 1：权限不足

**症状：**
```
bash: ./scripts/build.sh: Permission denied
```

**解决方案：**
```bash
chmod +x ./scripts/*.sh
```

---

### 问题 2：找不到模拟器或 iOS 版本不兼容

**症状：**
```
❌ 错误: 未找到模拟器 'iPhone 16'
或
App installation failed: "LanRead" Requires a Newer Version of iOS
```

**解决方案：**
```bash
# 1. 查看可用模拟器
xcrun simctl list devices available

# 2. 使用支持 iOS 18.2+ 的模拟器
./scripts/run.sh "iPhone 16"
./scripts/run.sh "iPhone 16 Pro"

# 3. 或在 Xcode 中添加新模拟器
# Xcode → Window → Devices and Simulators → Simulators → +
# 选择 iPhone 16 系列，iOS 18.2 或更高版本
```

**详细说明**: 由于 Xcode 16.4 构建的应用需要 iOS 18.5+，请使用 iPhone 16 系列模拟器。详见 [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)

---

### 问题 3：编译失败

**症状：**
```
❌ 编译失败！
```

**解决方案：**
```bash
# 1. 查看详细错误日志
cat build.log | grep error

# 2. 清理并重新编译
./scripts/build.sh clean
./scripts/build.sh

# 3. 在 Xcode 中打开项目检查错误
open "Isla Reader.xcodeproj"
```

---

### 问题 4：应用未找到

**症状：**
```
❌ 错误: 未找到编译好的应用
```

**解决方案：**
```bash
# 先编译项目
./scripts/build.sh

# 然后再运行
./scripts/run.sh
```

---

### 问题 5：模拟器无法启动

**症状：**
模拟器窗口打开但显示黑屏或卡住

**解决方案：**
```bash
# 1. 关闭所有模拟器
killall Simulator

# 2. 重置模拟器
xcrun simctl shutdown all
xcrun simctl erase all

# 3. 重新启动
./scripts/run.sh
```

---

## 📝 日志文件

脚本会生成以下日志文件：

| 文件 | 说明 |
|------|------|
| `build.log` | 完整的编译日志 |
| `build/Logs/Build/` | Xcode 构建日志 |

**查看日志：**
```bash
# 查看编译错误
cat build.log | grep -i error

# 查看编译警告
cat build.log | grep -i warning

# 查看完整日志
less build.log
```

---

## 🎯 使用场景示例

### 场景 1：快速测试修改

```bash
# 1. 修改代码（在 Cursor 中编辑）
# 2. 保存文件
# 3. 运行
./scripts/dev.sh

# 应用会自动编译、启动，并显示日志
```

### 场景 2：在不同设备上测试

```bash
# iPhone 测试
./scripts/run.sh "iPhone 16"

# iPad 测试
./scripts/run.sh "iPad Pro 13-inch (M4)"
```

### 场景 3：Debug 特定功能

```bash
# 1. 在代码中添加 print 语句
print("🔍 DEBUG: 进入 loadBook 函数")

# 2. 编译运行
./scripts/dev.sh

# 3. 在控制台查找你的日志
# 输出会实时显示在终端
```

### 场景 4：自动化 CI/CD

```bash
#!/bin/bash
# 在 CI/CD 管道中使用

# 编译
if ./scripts/build.sh release; then
    echo "✅ 编译成功"
    
    # 运行测试
    xcodebuild test -project "Isla Reader.xcodeproj" \
        -scheme "LanRead" \
        -destination 'platform=iOS Simulator,name=iPhone 16'
else
    echo "❌ 编译失败"
    exit 1
fi
```

---

## 💡 提示和技巧

### 1. 使用别名快速访问

在 `~/.zshrc` 或 `~/.bashrc` 中添加：

```bash
alias isla-build='cd "/Users/guoliang/Desktop/workspace/code/SelfProject/IslaProject/LanRead-ios/Isla Reader" && ./scripts/build.sh'
alias isla-run='cd "/Users/guoliang/Desktop/workspace/code/SelfProject/IslaProject/LanRead-ios/Isla Reader" && ./scripts/run.sh'
alias isla-dev='cd "/Users/guoliang/Desktop/workspace/code/SelfProject/IslaProject/LanRead-ios/Isla Reader" && ./scripts/dev.sh'
```

然后可以在任何目录直接运行：
```bash
isla-dev
```

### 2. 监控文件变化自动编译

安装 `fswatch` 并创建监控脚本：

```bash
brew install fswatch

# 创建监控脚本
cat > scripts/watch.sh << 'EOF'
#!/bin/bash
echo "👀 监控文件变化..."
fswatch -o "Isla Reader/" | xargs -n1 -I{} ./scripts/dev.sh
EOF

chmod +x scripts/watch.sh
./scripts/watch.sh
```

### 3. 加速编译

```bash
# 在 build.sh 中添加并行编译
# 找到 xcodebuild build 命令，添加参数：
-jobs $(sysctl -n hw.ncpu)
```

---

## 📚 相关资源

- [Xcode 命令行工具文档](https://developer.apple.com/library/archive/technotes/tn2339/_index.html)
- [simctl 命令参考](https://nshipster.com/simctl/)
- [iOS 日志最佳实践](https://developer.apple.com/documentation/os/logging)

---

## 🤝 贡献

如果你对脚本有改进建议，欢迎修改并提交！

---

**最后更新**: 2025-10-21  
**版本**: 1.0.0

