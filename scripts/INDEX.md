# 📑 脚本工具包索引

## 🚀 一句话开始

```bash
./scripts/dev.sh
```

这一个命令会：编译项目 → 启动模拟器 → 安装应用 → 运行应用 → **实时显示日志**

---

## 📂 文件结构

```
scripts/
│
├── 🔧 可执行脚本（.sh）
│   ├── build.sh          # 编译脚本
│   ├── run.sh            # 运行脚本（带实时日志输出）
│   ├── dev.sh            # 一键开发（编译+运行）⭐ 最常用
│   ├── simulator.sh      # 模拟器管理工具
│   └── test-scripts.sh   # 环境测试脚本
│
└── 📚 文档（.md）
    ├── INDEX.md          # 本文件（快速索引）
    ├── SUMMARY.md        # 总结和概览 ⭐ 先看这个
    ├── QUICK_START.md    # 快速参考（命令速查表）
    ├── README.md         # 完整文档
    └── DEMO.md           # 使用演示和场景示例
```

---

## ⚡️ 快速开始（3步）

### 1️⃣ 第一次使用：测试环境

```bash
cd "/Users/guoliang/Desktop/workspace/code/SelfProject/IslaProject/IslaBooks-ios/Isla Reader"
./scripts/test-scripts.sh
```

### 2️⃣ 日常开发：一键运行

```bash
./scripts/dev.sh
```

### 3️⃣ 看到日志！

终端会实时显示应用的所有输出：
```
📋 应用控制台日志输出（按 Ctrl+C 退出）:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

2025-10-21 14:30:21.123 Isla Reader[1234] 📚 你的日志输出
2025-10-21 14:30:21.456 Isla Reader[1234] ✅ 这里会显示所有 print()
```

---

## 📖 文档阅读顺序

### 🎯 如果你想快速上手

1. **看这个** → `SUMMARY.md` （5分钟了解全部功能）
2. **运行** → `./scripts/dev.sh` （实际体验）
3. **需要时查** → `QUICK_START.md` （命令速查表）

### 📚 如果你想深入学习

1. **基础** → `QUICK_START.md` （命令速查表）
2. **详细** → `README.md` （完整文档）
3. **实战** → `DEMO.md` （场景示例）

### 🆘 如果你遇到问题

1. **运行测试** → `./scripts/test-scripts.sh`
2. **查看排查** → `README.md` 中的"常见问题解决"部分
3. **查看日志** → `cat build.log | grep error`

---

## 🎯 核心功能（三个需求）

### ✅ 需求 1：编译脚本

```bash
./scripts/build.sh          # Debug 模式
./scripts/build.sh release  # Release 模式
./scripts/build.sh clean    # 清理后编译
```

### ✅ 需求 2：启动虚拟机并运行

```bash
./scripts/run.sh                    # 默认模拟器
./scripts/run.sh "iPhone 15 Pro"   # 指定模拟器
```

### ✅ 需求 3：实时日志输出 ⭐️

**这是核心功能！**

运行 `./scripts/run.sh` 或 `./scripts/dev.sh` 后，终端会实时显示应用的所有日志输出。

**在代码中输出：**
```swift
print("📚 你的调试信息")
// 会立即在终端看到输出
```

---

## 💡 常用命令速查

| 场景 | 命令 |
|------|------|
| 🚀 **日常开发（最常用）** | `./scripts/dev.sh` |
| 📦 编译项目 | `./scripts/build.sh` |
| 🏃 运行应用+日志 | `./scripts/run.sh` |
| 📱 列出模拟器 | `./scripts/simulator.sh list` |
| 📋 只看日志 | `./scripts/simulator.sh logs` |
| 📊 查看状态 | `./scripts/simulator.sh status` |
| 🗑️ 重置模拟器 | `./scripts/simulator.sh reset` |
| 📸 截图 | `./scripts/simulator.sh screenshot` |
| 🎥 录像 | `./scripts/simulator.sh record` |
| 🧪 测试环境 | `./scripts/test-scripts.sh` |

---

## 🎨 脚本特性

### ✨ 用户友好

- ✅ 彩色输出（成功=绿色，错误=红色，警告=黄色）
- ✅ 清晰的进度提示和 emoji 图标
- ✅ 详细的错误信息和解决建议
- ✅ 自动化程度高，减少手动操作

### 🔧 功能强大

- ✅ **实时日志输出**（核心功能）
- ✅ 支持多种模拟器设备
- ✅ 支持 Debug 和 Release 模式
- ✅ 模拟器管理（启动/停止/重置）
- ✅ 截图和录像功能
- ✅ 应用状态检查

### 🛡️ 可靠稳定

- ✅ 完善的错误处理
- ✅ 环境检测和验证
- ✅ 详细的日志记录
- ✅ 通过测试验证

---

## 📋 脚本详细说明

### 1. `build.sh` - 编译脚本

**功能：** 编译 iOS 项目

**用法：**
```bash
./scripts/build.sh [clean|debug|release]
```

**特性：**
- 支持 Debug/Release 模式
- 支持清理编译
- 显示编译进度和耗时
- 生成编译日志（build.log）

**输出：** `./build/Build/Products/Debug-iphonesimulator/Isla Reader.app`

---

### 2. `run.sh` - 运行脚本 ⭐️

**功能：** 启动模拟器、安装应用、运行并**实时显示日志**

**用法：**
```bash
./scripts/run.sh [simulator_name]
```

**特性：**
- 自动启动模拟器
- 自动安装应用
- **实时输出控制台日志**（这是你需要的！）
- 按 Ctrl+C 退出日志监控

**示例：**
```bash
./scripts/run.sh                    # iPhone 15
./scripts/run.sh "iPhone 15 Pro"   # iPhone 15 Pro
./scripts/run.sh "iPad Pro"         # iPad Pro
```

---

### 3. `dev.sh` - 开发脚本 ⭐️⭐️

**功能：** 一键完成编译+运行+日志输出（**最推荐！**）

**用法：**
```bash
./scripts/dev.sh [simulator_name]
```

**执行流程：**
1. 📦 编译项目（Debug）
2. 🚀 启动模拟器
3. 📱 安装应用
4. 🏃 运行应用
5. 📋 实时显示日志

这是最常用的命令！

---

### 4. `simulator.sh` - 模拟器管理工具

**功能：** 管理 iOS 模拟器的各种操作

**用法：**
```bash
./scripts/simulator.sh <command> [options]
```

**命令列表：**
- `list` - 列出所有可用模拟器
- `start [name]` - 启动指定模拟器
- `stop [name]` - 关闭模拟器
- `reset [name]` - 重置模拟器数据
- `logs` - 查看应用日志（实时）
- `status` - 查看应用安装状态
- `uninstall` - 卸载应用
- `screenshot` - 截图
- `record [sec]` - 录制视频

**示例：**
```bash
./scripts/simulator.sh list
./scripts/simulator.sh start "iPhone 15"
./scripts/simulator.sh logs
./scripts/simulator.sh screenshot
```

---

### 5. `test-scripts.sh` - 环境测试脚本

**功能：** 检测开发环境是否配置正确

**用法：**
```bash
./scripts/test-scripts.sh
```

**检测项目：**
- Xcode 和命令行工具
- 脚本文件和权限
- 项目文件
- 可用的模拟器
- 编译输出

---

## 💡 使用技巧

### 技巧 1：设置别名（推荐）

在 `~/.zshrc` 中添加：
```bash
alias isla-dev='cd "/Users/guoliang/Desktop/workspace/code/SelfProject/IslaProject/IslaBooks-ios/Isla Reader" && ./scripts/dev.sh'
```

然后可以在任何目录：
```bash
isla-dev  # 快速启动
```

### 技巧 2：日志过滤

```bash
# 只显示包含特定关键字的日志
./scripts/run.sh | grep "BookManager"

# 只显示错误
./scripts/run.sh | grep -i error
```

### 技巧 3：组合命令

```bash
# 清理后编译并运行
./scripts/build.sh clean && ./scripts/run.sh
```

---

## 🆘 遇到问题？

### 第一步：运行环境测试

```bash
./scripts/test-scripts.sh
```

### 第二步：查看错误日志

```bash
cat build.log | grep -i error
```

### 第三步：查看文档

- 快速问题 → `QUICK_START.md`
- 详细排查 → `README.md` 的"常见问题解决"部分

---

## 📞 更多信息

| 文档 | 内容 | 适合 |
|------|------|------|
| `INDEX.md` | 本文件，快速索引 | 查找文档 |
| `SUMMARY.md` | 总结和概览 | **首次了解** ⭐️ |
| `QUICK_START.md` | 命令速查表 | 日常使用 |
| `README.md` | 完整文档 | 深入学习 |
| `DEMO.md` | 使用演示 | 实战练习 |

---

## ✅ 环境状态

运行测试结果：
```
✅ xcodebuild 命令
✅ xcrun 命令
✅ xcode-select 安装
✅ Xcode 16.4
✅ 所有脚本可执行
✅ 项目文件完整
✅ 找到 15 个 iPhone 模拟器
✅ 已编译的应用存在

🎉 所有测试通过！环境配置正确。
```

---

## 🎉 开始使用

记住这一个命令就够了：

```bash
./scripts/dev.sh
```

它会自动完成所有工作，并**实时显示控制台日志**！

Happy Coding! 🚀📱✨

---

**创建时间：** 2025-10-21  
**项目：** Isla Reader  
**作者：** AI Assistant

