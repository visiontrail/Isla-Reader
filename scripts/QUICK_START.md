# 🚀 快速开始 - 命令速查表

## ⚡️ 最常用的三个命令

```bash
# 1. 一键编译并运行（推荐！）
./scripts/dev.sh

# 2. 只编译
./scripts/build.sh

# 3. 只运行（需要先编译）
./scripts/run.sh
```

---

## 📦 编译命令

```bash
# Debug 模式编译（开发用）
./scripts/build.sh
./scripts/build.sh debug

# Release 模式编译（性能优化）
./scripts/build.sh release

# 清理后编译（解决编译问题）
./scripts/build.sh clean
```

**编译成功后的应用位置：**
```
./build/Build/Products/Debug-iphonesimulator/LanRead.app
```

---

## 🏃 运行命令

```bash
# 使用默认模拟器 (iPhone 15)
./scripts/run.sh

# 使用指定模拟器
./scripts/run.sh "iPhone 15 Pro"
./scripts/run.sh "iPhone 16"
./scripts/run.sh "iPad Pro (12.9-inch)"
```

**特性：**
- ✅ 自动启动模拟器
- ✅ 自动安装应用
- ✅ **实时输出控制台日志**
- ✅ 按 Ctrl+C 退出

---

## 🔧 模拟器管理

```bash
# 列出所有可用模拟器
./scripts/simulator.sh list

# 启动指定模拟器
./scripts/simulator.sh start "iPhone 15"

# 关闭所有模拟器
./scripts/simulator.sh stop

# 重置模拟器数据
./scripts/simulator.sh reset "iPhone 15"

# 查看应用安装状态
./scripts/simulator.sh status

# 卸载应用
./scripts/simulator.sh uninstall

# 查看应用日志
./scripts/simulator.sh logs

# 截图
./scripts/simulator.sh screenshot

# 录制视频（默认30秒）
./scripts/simulator.sh record
./scripts/simulator.sh record 60
```

---

## 💡 常见使用场景

### 场景 1：第一次运行项目

```bash
cd "/Users/guoliang/Desktop/workspace/code/SelfProject/IslaProject/IslaBooks-ios/Isla Reader"
./scripts/dev.sh
```

### 场景 2：修改代码后快速测试

```bash
# 在 Cursor 中保存代码后
./scripts/dev.sh
```

### 场景 3：查看应用输出日志

```bash
# 方法 1: 运行时自动显示
./scripts/run.sh

# 方法 2: 单独查看日志
./scripts/simulator.sh logs
```

### 场景 4：在不同设备上测试

```bash
# 先查看可用设备
./scripts/simulator.sh list

# 在 iPhone 上测试
./scripts/run.sh "iPhone 15"

# 在 iPad 上测试
./scripts/run.sh "iPad Pro (12.9-inch)"
```

### 场景 5：编译失败排查

```bash
# 清理重新编译
./scripts/build.sh clean

# 查看详细错误
cat build.log | grep -i error

# 或在 Xcode 中查看
open "Isla Reader.xcodeproj"
```

### 场景 6：模拟器卡死或异常

```bash
# 关闭所有模拟器
./scripts/simulator.sh stop

# 重置模拟器
./scripts/simulator.sh reset "iPhone 15"

# 重新运行
./scripts/dev.sh
```

---

## 🎯 开发工作流推荐

### 工作流 A：快速迭代（推荐）

```bash
# 1. 启动开发
./scripts/dev.sh

# 2. 修改代码（在 Cursor 中）
# 3. 保存文件
# 4. 重新运行
./scripts/dev.sh

# 日志会实时显示在终端
```

### 工作流 B：分步执行

```bash
# 1. 编译
./scripts/build.sh

# 2. 运行
./scripts/run.sh

# 3. 查看日志（如果需要）
./scripts/simulator.sh logs
```

### 工作流 C：多设备测试

```bash
# 编译一次
./scripts/build.sh

# 在不同设备上运行
./scripts/run.sh "iPhone 15"
./scripts/run.sh "iPhone 15 Pro"
./scripts/run.sh "iPad Pro (12.9-inch)"
```

---

## 📝 日志输出说明

运行 `./scripts/run.sh` 或 `./scripts/dev.sh` 后，终端会实时显示应用日志。

### 在代码中输出日志：

```swift
// 方法 1: 简单 print
print("📚 加载书籍: \(bookTitle)")

// 方法 2: 使用 OSLog（推荐）
import os
let logger = Logger(subsystem: "LeoGuo.Isla-Reader", category: "BookManager")
logger.info("📚 加载书籍: \(bookTitle)")
logger.error("❌ 错误: \(error)")
```

### 过滤日志输出：

```bash
# 只显示包含 "BookManager" 的日志
./scripts/run.sh | grep "BookManager"

# 只显示错误
./scripts/run.sh | grep -i error

# 排除系统日志
./scripts/run.sh | grep -v "UIKit"
```

---

## 🆘 常见问题快速解决

| 问题 | 命令 |
|------|------|
| 权限不足 | `chmod +x ./scripts/*.sh` |
| 编译失败 | `./scripts/build.sh clean` 然后 `./scripts/build.sh` |
| 找不到应用 | 先运行 `./scripts/build.sh` |
| 模拟器卡死 | `./scripts/simulator.sh stop` 然后 `./scripts/simulator.sh start` |
| 模拟器数据错误 | `./scripts/simulator.sh reset "iPhone 15"` |
| 查看可用模拟器 | `./scripts/simulator.sh list` |
| 卸载应用 | `./scripts/simulator.sh uninstall` |

---

## 🔗 快捷别名设置（可选）

在 `~/.zshrc` 或 `~/.bashrc` 中添加：

```bash
# Isla Reader 别名
ISLA_DIR="/Users/guoliang/Desktop/workspace/code/SelfProject/IslaProject/IslaBooks-ios/Isla Reader"
alias isla-dev='cd "$ISLA_DIR" && ./scripts/dev.sh'
alias isla-build='cd "$ISLA_DIR" && ./scripts/build.sh'
alias isla-run='cd "$ISLA_DIR" && ./scripts/run.sh'
alias isla-sim='cd "$ISLA_DIR" && ./scripts/simulator.sh'
alias isla-logs='cd "$ISLA_DIR" && ./scripts/simulator.sh logs'
```

重新加载配置：
```bash
source ~/.zshrc
```

使用别名（可在任何目录）：
```bash
isla-dev              # 编译并运行
isla-build            # 只编译
isla-run              # 只运行
isla-sim list         # 列出模拟器
isla-logs             # 查看日志
```

---

## 📊 脚本功能对比

| 脚本 | 用途 | 适用场景 |
|------|------|----------|
| `dev.sh` | 一键编译+运行 | 日常开发（最常用）|
| `build.sh` | 只编译项目 | 需要单独编译 |
| `run.sh` | 只运行应用 | 已编译后快速测试 |
| `simulator.sh` | 模拟器管理 | 管理模拟器、查看状态 |

---

## 📚 更多信息

- 详细文档：查看 `scripts/README.md`
- 模拟器帮助：运行 `./scripts/simulator.sh help`
- 项目文档：查看 `Isla Reader/docs/`

---

**记住这一个命令就够了：**
```bash
./scripts/dev.sh
```

它会自动完成编译、启动模拟器、安装应用、运行并显示日志。🎉

