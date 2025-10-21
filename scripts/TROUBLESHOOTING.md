# 故障排除指南 (Troubleshooting Guide)

## iOS 版本不兼容问题

### 问题描述
当运行 `./scripts/dev.sh` 时，可能会遇到以下错误：

```
App installation failed: "Isla Reader" Requires a Newer Version of iOS
You need to update this iPhone to iOS 18.5 to install this app.
```

### 原因
这个问题是由于 Xcode 16.4 构建的应用需要较新的 iOS 版本（18.5+），而默认的模拟器运行的是较旧的 iOS 版本（如 17.2）。

### 解决方案

#### 方案一：使用支持的模拟器（推荐）
脚本已经更新为使用 iPhone 16 模拟器（iOS 18.6），直接运行即可：

```bash
./scripts/dev.sh
```

#### 方案二：手动指定模拟器
如果你想使用其他支持 iOS 18.2+ 的模拟器，可以这样：

```bash
# 查看可用的模拟器
xcrun simctl list devices available | grep iPhone

# 使用特定的模拟器运行
./scripts/dev.sh "iPhone 16 Pro"
```

#### 方案三：创建新的模拟器
如果没有合适的模拟器，可以在 Xcode 中创建一个：

1. 打开 Xcode
2. Window → Devices and Simulators
3. 点击 "+" 创建新模拟器
4. 选择 iPhone 16 或更新的设备
5. 选择 iOS 18.2 或更高版本

### 可用的模拟器
根据你的系统，以下模拟器应该可以使用：

- iPhone 16 (iOS 18.2, 18.6)
- iPhone 16 Plus (iOS 18.2, 18.6)
- iPhone 16 Pro (iOS 18.2, 18.6)
- iPhone 16 Pro Max (iOS 18.2, 18.6)

### 技术细节
- **项目部署目标**: iOS 16.0 (IPHONEOS_DEPLOYMENT_TARGET)
- **Xcode 版本**: 16.4
- **构建 SDK**: iOS 18.5+
- **最低模拟器要求**: iOS 18.2+
- **注意**: 项目使用了 iOS 16+ 的 API (如 NavigationSplitView)，因此最低支持 iOS 16.0

---

## API 可用性编译错误

### 问题描述
编译时遇到类似以下的错误：

```
error: 'NavigationSplitView' is only available in iOS 16.0 or newer
```

### 原因
代码中使用了 iOS 16.0+ 的 API（如 `NavigationSplitView`），但项目的部署目标设置为较低版本。

### 解决方案
项目配置已更新为 iOS 16.0 作为最低部署目标。如果您仍然遇到此错误：

1. 清理构建缓存：
```bash
./scripts/build.sh clean
rm -rf build/
```

2. 重新编译：
```bash
./scripts/build.sh
```

3. 如果问题仍然存在，在 Xcode 中检查设置：
   - 打开项目：`open "Isla Reader.xcodeproj"`
   - 选择项目 → Target → Isla Reader
   - General → Deployment Info → Minimum Deployments
   - 确保设置为 iOS 16.0 或更高

---

## iOS Version Compatibility Issue

### Problem Description
When running `./scripts/dev.sh`, you may encounter this error:

```
App installation failed: "Isla Reader" Requires a Newer Version of iOS
You need to update this iPhone to iOS 18.5 to install this app.
```

### Cause
This happens because apps built with Xcode 16.4 require a newer iOS version (18.5+), while the default simulator is running an older iOS version (e.g., 17.2).

### Solutions

#### Solution 1: Use Supported Simulator (Recommended)
The scripts have been updated to use iPhone 16 simulator (iOS 18.6), just run:

```bash
./scripts/dev.sh
```

#### Solution 2: Manually Specify Simulator
To use a different simulator with iOS 18.2+:

```bash
# List available simulators
xcrun simctl list devices available | grep iPhone

# Run with specific simulator
./scripts/dev.sh "iPhone 16 Pro"
```

#### Solution 3: Create New Simulator
If no suitable simulator exists, create one in Xcode:

1. Open Xcode
2. Window → Devices and Simulators
3. Click "+" to create new simulator
4. Select iPhone 16 or newer
5. Choose iOS 18.2 or higher

### Available Simulators
Based on your system, these simulators should work:

- iPhone 16 (iOS 18.2, 18.6)
- iPhone 16 Plus (iOS 18.2, 18.6)
- iPhone 16 Pro (iOS 18.2, 18.6)
- iPhone 16 Pro Max (iOS 18.2, 18.6)

### Technical Details
- **Deployment Target**: iOS 16.0 (IPHONEOS_DEPLOYMENT_TARGET)
- **Xcode Version**: 16.4
- **Build SDK**: iOS 18.5+
- **Minimum Simulator Required**: iOS 18.2+
- **Note**: The project uses iOS 16+ APIs (such as NavigationSplitView), so it requires iOS 16.0 minimum

---

## API Availability Compilation Error

### Problem Description
You may encounter compilation errors like:

```
error: 'NavigationSplitView' is only available in iOS 16.0 or newer
```

### Cause
The code uses iOS 16.0+ APIs (such as `NavigationSplitView`), but the project's deployment target is set to a lower version.

### Solution
The project configuration has been updated to iOS 16.0 as the minimum deployment target. If you still encounter this error:

1. Clean build cache:
```bash
./scripts/build.sh clean
rm -rf build/
```

2. Rebuild:
```bash
./scripts/build.sh
```

3. If the issue persists, check settings in Xcode:
   - Open project: `open "Isla Reader.xcodeproj"`
   - Select project → Target → Isla Reader
   - General → Deployment Info → Minimum Deployments
   - Ensure it's set to iOS 16.0 or higher

