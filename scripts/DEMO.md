# 🎬 脚本使用演示

这是一个简单的演示教程，展示如何使用这些脚本进行 iOS 开发。

## 📂 脚本文件列表

```
scripts/
├── build.sh           # 编译脚本
├── run.sh             # 运行脚本（带日志输出）
├── dev.sh             # 开发脚本（编译+运行）
├── simulator.sh       # 模拟器管理脚本
├── test-scripts.sh    # 测试验证脚本
├── README.md          # 详细文档
├── QUICK_START.md     # 快速参考
└── DEMO.md            # 本文件
```

---

## 🎯 场景 1：第一次使用

### 步骤 1：验证环境

```bash
cd "/Users/guoliang/Desktop/workspace/code/SelfProject/IslaProject/LanRead-ios/Isla Reader"

# 测试环境是否正确配置
./scripts/test-scripts.sh
```

**预期输出：**
```
🎉 所有测试通过！环境配置正确。
```

### 步骤 2：一键运行

```bash
# 这一个命令会完成所有工作：编译、启动模拟器、安装应用、运行并显示日志
./scripts/dev.sh
```

**你会看到：**
1. ⚙️ 编译进度
2. ✅ 编译成功
3. 📱 模拟器启动
4. 📦 应用安装
5. 🚀 应用启动
6. 📋 **控制台日志实时输出**（这是你需要的！）

**日志示例：**
```
📋 应用控制台日志输出（按 Ctrl+C 退出）:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

2025-10-21 14:30:21.123 LanRead[1234:567890] 📚 应用启动
2025-10-21 14:30:21.456 LanRead[1234:567890] 🔧 初始化数据库
2025-10-21 14:30:21.789 LanRead[1234:567890] ✅ 准备就绪
```

按 `Ctrl+C` 可以停止日志监控（应用继续运行）。

---

## 🎯 场景 2：日常开发流程

### 使用场景：修改代码后快速测试

```bash
# 1. 在 Cursor 中修改代码
# 比如在 ContentView.swift 中添加：
# print("🎉 Hello from LanRead!")

# 2. 保存文件（Cmd+S）

# 3. 重新编译运行
./scripts/dev.sh

# 4. 在终端中会看到你的 print 输出：
# 🎉 Hello from LanRead!
```

---

## 🎯 场景 3：只查看日志（不重新编译）

### 如果应用已经在运行，只想查看日志：

```bash
./scripts/simulator.sh logs
```

这会连接到正在运行的应用，显示实时日志。

---

## 🎯 场景 4：分步执行（高级用法）

### 有时候你可能想分开执行编译和运行：

```bash
# 步骤 1: 编译
./scripts/build.sh

# 步骤 2: 运行（会自动显示日志）
./scripts/run.sh
```

### 或者指定不同的模拟器：

```bash
# 先看有哪些模拟器可用
./scripts/simulator.sh list

# 在 iPhone 15 Pro 上运行
./scripts/run.sh "iPhone 15 Pro"

# 在 iPad 上运行
./scripts/run.sh "iPad Pro (12.9-inch)"
```

---

## 🎯 场景 5：调试特定功能

### 假设你要调试书籍加载功能：

**步骤 1：在代码中添加日志**

```swift
// BookManager.swift
func loadBook(id: String) {
    print("🔍 [DEBUG] 开始加载书籍: \(id)")
    
    // ... 你的代码 ...
    
    print("🔍 [DEBUG] 书籍元数据: \(metadata)")
    
    // ... 更多代码 ...
    
    print("✅ [DEBUG] 书籍加载完成")
}
```

**步骤 2：运行应用**

```bash
./scripts/dev.sh
```

**步骤 3：在终端查看你的调试日志**

你会实时看到：
```
🔍 [DEBUG] 开始加载书籍: book-123
🔍 [DEBUG] 书籍元数据: Book(title: "Test", author: "...")
✅ [DEBUG] 书籍加载完成
```

**步骤 4：过滤日志（如果输出太多）**

```bash
# 只显示包含 [DEBUG] 的日志
./scripts/run.sh | grep "\[DEBUG\]"

# 只显示你关心的特定功能
./scripts/run.sh | grep "BookManager"
```

---

## 🎯 场景 6：多设备测试

### 在不同设备上测试 UI 布局：

```bash
# 编译一次
./scripts/build.sh

# 在 iPhone 15 上测试
./scripts/run.sh "iPhone 15"
# 查看显示效果，按 Ctrl+C

# 在 iPhone 15 Pro Max 上测试
./scripts/run.sh "iPhone 15 Pro Max"
# 查看大屏幕效果，按 Ctrl+C

# 在 iPad 上测试
./scripts/run.sh "iPad Pro (12.9-inch)"
# 查看 iPad 布局
```

---

## 🎯 场景 7：模拟器管理

### 查看模拟器状态

```bash
# 查看所有可用模拟器
./scripts/simulator.sh list

# 查看应用安装状态
./scripts/simulator.sh status
```

**输出示例：**
```
📊 应用状态
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

运行中的模拟器: iPhone 15
UDID: 2366B76D-897D-41CC-B7B9-E674E56CF059

✅ 应用已安装
Bundle ID: LeoGuo.Isla-Reader
容器路径: /Users/.../Data/Containers/...
```

### 重置模拟器（解决问题）

```bash
# 当模拟器出现问题时
./scripts/simulator.sh reset "iPhone 15"

# 会提示确认
确认重置？(y/N) y
```

### 截图和录制

```bash
# 截图
./scripts/simulator.sh screenshot
# 会自动保存并打开图片

# 录制视频（30秒）
./scripts/simulator.sh record

# 录制60秒
./scripts/simulator.sh record 60
```

---

## 🎯 场景 8：解决编译错误

### 当编译失败时：

```bash
# 尝试清理后重新编译
./scripts/build.sh clean

# 查看详细错误信息
cat build.log | grep -i error

# 如果还是有问题，在 Xcode 中打开
open "Isla Reader.xcodeproj"
```

---

## 🎯 场景 9：自动化工作流

### 创建自己的自动化脚本

```bash
#!/bin/bash
# my-workflow.sh

# 1. 清理旧构建
echo "🧹 清理..."
./scripts/build.sh clean

# 2. 编译
echo "📦 编译..."
./scripts/build.sh

# 3. 在多个设备上测试
echo "📱 测试 iPhone..."
./scripts/run.sh "iPhone 15" &
PID1=$!

sleep 5
kill $PID1

echo "📱 测试 iPad..."
./scripts/run.sh "iPad Pro (12.9-inch)" &
PID2=$!

sleep 5
kill $PID2

echo "✅ 完成"
```

---

## 💡 实用技巧

### 技巧 1：使用别名

在 `~/.zshrc` 中添加：
```bash
alias isla='cd "/Users/guoliang/Desktop/workspace/code/SelfProject/IslaProject/LanRead-ios/Isla Reader"'
alias isla-dev='isla && ./scripts/dev.sh'
```

然后可以在任何地方：
```bash
isla-dev  # 快速启动
```

### 技巧 2：后台查看日志

```bash
# 运行应用但不阻塞终端
./scripts/dev.sh > dev.log 2>&1 &

# 在另一个终端查看日志
tail -f dev.log
```

### 技巧 3：组合命令

```bash
# 编译成功后才运行
./scripts/build.sh && ./scripts/run.sh

# 运行前先关闭所有模拟器
./scripts/simulator.sh stop && ./scripts/dev.sh
```

---

## 📊 命令速查表

| 你想要... | 使用命令 |
|---------|---------|
| 快速开始 | `./scripts/dev.sh` |
| 只编译 | `./scripts/build.sh` |
| 只运行+日志 | `./scripts/run.sh` |
| 查看日志 | `./scripts/simulator.sh logs` |
| 列出模拟器 | `./scripts/simulator.sh list` |
| 查看状态 | `./scripts/simulator.sh status` |
| 截图 | `./scripts/simulator.sh screenshot` |
| 录像 | `./scripts/simulator.sh record` |
| 重置模拟器 | `./scripts/simulator.sh reset` |
| 测试环境 | `./scripts/test-scripts.sh` |

---

## 🎓 实战练习

### 练习 1：Hello World 日志

1. 打开 `Isla Reader/ContentView.swift`
2. 在 `body` 前添加：
   ```swift
   init() {
       print("👋 ContentView 初始化")
   }
   ```
3. 运行 `./scripts/dev.sh`
4. 在终端看到输出：`👋 ContentView 初始化`

### 练习 2：不同设备测试

1. 运行 `./scripts/simulator.sh list`
2. 选择3个不同的设备
3. 分别运行：
   ```bash
   ./scripts/run.sh "设备1"
   ./scripts/run.sh "设备2"
   ./scripts/run.sh "设备3"
   ```
4. 观察UI在不同屏幕尺寸的表现

### 练习 3：调试一个功能

1. 选择项目中的任意一个函数
2. 在函数开头、中间、结尾添加 print 语句
3. 运行 `./scripts/dev.sh`
4. 在终端观察函数执行流程

---

## ❓ 常见问题

**Q: 日志输出太多怎么办？**
```bash
# 使用 grep 过滤
./scripts/run.sh | grep "你关心的关键字"
```

**Q: 如何停止应用但继续看日志？**
```bash
# 日志会持续输出直到按 Ctrl+C
# 应用在模拟器中继续运行
```

**Q: 如何完全关闭一切？**
```bash
# 按 Ctrl+C 停止日志
# 然后关闭模拟器
./scripts/simulator.sh stop
```

**Q: 脚本执行权限不够？**
```bash
chmod +x ./scripts/*.sh
```

---

## 🎉 恭喜！

你现在已经掌握了使用命令行进行 iOS 开发的基础！

**记住最重要的一个命令：**
```bash
./scripts/dev.sh
```

它会：
✅ 编译你的代码
✅ 启动模拟器
✅ 安装应用
✅ 运行应用
✅ **实时显示控制台日志**

Happy Coding! 🚀

