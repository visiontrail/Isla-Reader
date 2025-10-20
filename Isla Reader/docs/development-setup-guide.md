# IslaBooks iOS 开发环境搭建指南

## 文档信息
- **版本**: v1.0.0
- **日期**: 2025-08-27
- **适用对象**: 首次搭建iOS开发环境的开发者
- **预计时间**: 2-4小时

---

## 📋 前置条件检查

### 系统要求
- **操作系统**: macOS 13.0+ (Ventura) 或更新版本
- **硬件**: Mac with Apple Silicon (M1/M2) 或 Intel Mac
- **存储空间**: 至少 50GB 可用空间
- **网络**: 稳定的网络连接（下载Xcode需要）

### 验证系统信息
```bash
# 检查macOS版本
sw_vers

# 检查可用存储空间
df -h

# 检查芯片类型
uname -m
```

---

## 🛠️ 第一步：安装Xcode

### 方法一：从App Store安装（推荐）

1. **打开App Store**
   ```bash
   open /Applications/App\ Store.app
   ```

2. **搜索并安装Xcode**
   - 在搜索框输入 "Xcode"
   - 找到 Apple 官方的 Xcode
   - 点击"获取"或"安装"
   - ⏱️ 下载时间：约 30-60 分钟（取决于网络速度）

3. **验证安装**
   ```bash
   # 验证Xcode版本
   xcodebuild -version
   
   # 应该输出类似：
   # Xcode 15.0
   # Build version 15A240d
   ```

### 方法二：从Apple Developer网站下载

1. **访问 Apple Developer**
   - 打开 https://developer.apple.com/download/
   - 使用Apple ID登录

2. **下载Xcode**
   - 找到最新版本的Xcode
   - 下载.xip文件
   - 双击安装

### 安装命令行工具
```bash
# 安装Xcode命令行工具
xcode-select --install

# 验证安装
xcode-select -p
# 应该输出：/Applications/Xcode.app/Contents/Developer
```

---

## 🔑 第二步：Apple Developer账号配置

### 创建Apple ID（如果还没有）
1. 访问 https://appleid.apple.com/
2. 点击"创建您的Apple ID"
3. 填写必要信息并验证

### 配置开发者账号

#### 个人开发者账号（免费）
```bash
# 打开Xcode
open /Applications/Xcode.app
```

1. **添加Apple ID**
   - Xcode → Preferences → Accounts
   - 点击左下角的"+"
   - 选择"Apple ID"
   - 输入您的Apple ID和密码

2. **创建开发团队**
   - 选择您的Apple ID
   - 点击"Manage Certificates..."
   - 如果没有证书，点击"+"创建开发证书

#### 付费开发者账号（可选）
- 访问 https://developer.apple.com/programs/
- 注册Apple Developer Program ($99/年)
- 获得更多功能（TestFlight、App Store发布等）

---

## 📱 第三步：项目初始化

### 创建新的iOS项目

1. **启动Xcode**
   ```bash
   open /Applications/Xcode.app
   ```

2. **创建新项目**
   - 选择"Create a new Xcode project"
   - 选择"iOS" → "App"
   - 配置项目信息：
     ```
     Product Name: IslaBooks
     Team: 选择您的开发团队
     Organization Identifier: com.yourname.islabooks
     Bundle Identifier: com.yourname.islabooks
     Language: Swift
     Interface: SwiftUI
     Use Core Data: ✅ 勾选
     Include Tests: ✅ 勾选
     ```

3. **选择保存位置**
   ```
   建议路径: ~/Desktop/workspace/code/SelfProject/IslaProject/IslaBooks
   ```

### 项目基础配置

#### 配置Info.plist
在项目导航器中找到 `Info.plist`，添加以下配置：

```xml
<!-- 文档类型支持 -->
<key>CFBundleDocumentTypes</key>
<array>
    <dict>
        <key>CFBundleTypeName</key>
        <string>EPUB Document</string>
        <key>CFBundleTypeRole</key>
        <string>Viewer</string>
        <key>LSHandlerRank</key>
        <string>Owner</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>org.idpf.epub-container</string>
        </array>
    </dict>
    <dict>
        <key>CFBundleTypeName</key>
        <string>Plain Text Document</string>
        <key>CFBundleTypeRole</key>
        <string>Viewer</string>
        <key>LSHandlerRank</key>
        <string>Owner</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>public.plain-text</string>
        </array>
    </dict>
</array>

<!-- 权限描述 -->
<key>NSDocumentsFolderUsageDescription</key>
<string>访问文档文件夹以导入您的电子书文件</string>

<key>NSCloudKitUsageDescription</key>
<string>使用iCloud同步您的阅读进度和笔记</string>

<!-- App Transport Security -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
    <key>NSExceptionDomains</key>
    <dict>
        <key>api.islabooks.com</key>
        <dict>
            <key>NSExceptionRequiresForwardSecrecy</key>
            <false/>
        </dict>
    </dict>
</dict>
```

#### 配置Capabilities

1. **选择项目目标**
   - 在项目导航器中选择项目名称
   - 选择"IslaBooks" target

2. **添加Capabilities**
   - 点击"Signing & Capabilities"标签
   - 点击"+ Capability"
   - 添加以下能力：
     ```
     ✅ CloudKit
     ✅ iCloud (Documents)
     ✅ Background Modes
         - Background processing
         - Background fetch
     ✅ Associated Domains (可选)
     ✅ Push Notifications (可选)
     ```

---

## ☁️ 第四步：CloudKit配置

### 创建CloudKit容器

1. **访问CloudKit Dashboard**
   - 打开 https://icloud.developer.apple.com/
   - 使用您的Apple ID登录

2. **创建新容器**
   - 点击"+"创建新容器
   - 容器标识符: `iCloud.com.yourname.islabooks`
   - 确保与Bundle Identifier匹配

3. **配置Schema**
   
   创建以下Record Types：

   ```
   LibraryItem:
   - bookId: String (Queryable, Sortable)
   - status: String
   - tags: List(String)
   - isFavorite: Int64
   - addedAt: DateTime (Sortable)
   - lastReadAt: DateTime
   
   ReadingProgress:
   - libraryItemId: Reference(LibraryItem)
   - currentChapterId: String
   - currentPosition: Double
   - totalReadingTime: Int64
   - lastReadAt: DateTime (Sortable)
   
   Highlight:
   - bookId: String (Queryable)
   - chapterId: String (Queryable)
   - rangeStart: Int64
   - rangeEnd: Int64
   - text: String
   - note: String
   - color: String
   - createdAt: DateTime (Sortable)
   ```

4. **设置安全角色**
   - 所有Record Types设置为"Readable and Writable by Creator"

### 在Xcode中配置CloudKit

1. **添加CloudKit Capability**
   - 确保已在Capabilities中添加CloudKit
   - 选择刚创建的CloudKit容器

2. **验证配置**
   ```swift
   // 在AppDelegate或App.swift中添加测试代码
   import CloudKit
   
   func testCloudKitConnection() {
       let container = CKContainer.default()
       container.accountStatus { status, error in
           switch status {
           case .available:
               print("✅ CloudKit账号可用")
           case .noAccount:
               print("❌ 未登录iCloud账号")
           case .restricted:
               print("❌ iCloud账号受限")
           case .couldNotDetermine:
               print("❌ 无法确定账号状态")
           @unknown default:
               print("❌ 未知状态")
           }
       }
   }
   ```

---

## 📦 第五步：依赖管理配置

### 使用Swift Package Manager添加依赖

1. **在Xcode中添加Package**
   - File → Add Package Dependencies...
   - 添加以下依赖：

   ```
   ZIPFoundation:
   https://github.com/weichsel/ZIPFoundation.git
   
   CombineExt (可选):
   https://github.com/CombineCommunity/CombineExt.git
   ```

2. **验证依赖安装**
   ```swift
   // 在任意Swift文件中测试导入
   import ZIPFoundation
   import Combine
   // import CombineExt  // 如果添加了
   ```

---

## 🧪 第六步：详细测试验证

### 测试1: 基础编译测试

```bash
# 在项目根目录执行
cd ~/Desktop/workspace/code/SelfProject/IslaProject/IslaBooks

# 清理项目
xcodebuild clean -project IslaBooks.xcodeproj -scheme IslaBooks

# 编译项目
xcodebuild build -project IslaBooks.xcodeproj -scheme IslaBooks -destination 'platform=iOS Simulator,name=iPhone 15'
```

**预期结果**: 编译成功，无错误

### 测试2: 模拟器运行测试

1. **启动模拟器**
   ```bash
   # 列出可用的模拟器
   xcrun simctl list devices available
   
   # 启动iPhone 15模拟器
   open -a Simulator --args -CurrentDeviceUDID [DEVICE_UDID]
   ```

2. **运行应用**
   - 在Xcode中选择iPhone 15模拟器
   - 按Cmd+R运行项目
   - **预期结果**: 应用成功启动，显示默认界面

### 测试3: Core Data配置测试

创建测试文件 `CoreDataTests.swift`：

```swift
import XCTest
import CoreData
@testable import IslaBooks

class CoreDataTests: XCTestCase {
    
    func testPersistentStoreCreation() {
        let context = PersistenceController.shared.container.viewContext
        XCTAssertNotNil(context, "Core Data context should not be nil")
    }
    
    func testBookEntityCreation() {
        let context = PersistenceController.shared.container.viewContext
        let book = Book(context: context)
        book.id = UUID()
        book.title = "Test Book"
        book.authors = ["Test Author"]
        book.language = "zh-CN"
        book.source = "local"
        
        do {
            try context.save()
            XCTAssertTrue(true, "Book entity created successfully")
        } catch {
            XCTFail("Failed to save book entity: \(error)")
        }
    }
}
```

运行测试：
```bash
# 运行单元测试
xcodebuild test -project IslaBooks.xcodeproj -scheme IslaBooks -destination 'platform=iOS Simulator,name=iPhone 15'
```

### 测试4: CloudKit连接测试

创建测试文件 `CloudKitTests.swift`：

```swift
import XCTest
import CloudKit
@testable import IslaBooks

class CloudKitTests: XCTestCase {
    
    func testCloudKitAccountStatus() {
        let expectation = self.expectation(description: "CloudKit account status")
        
        let container = CKContainer.default()
        container.accountStatus { status, error in
            defer { expectation.fulfill() }
            
            if let error = error {
                XCTFail("CloudKit error: \(error)")
                return
            }
            
            switch status {
            case .available:
                XCTAssertTrue(true, "✅ CloudKit账号可用")
            case .noAccount:
                print("⚠️ 模拟器未登录iCloud账号（正常情况）")
            default:
                print("ℹ️ CloudKit状态: \(status)")
            }
        }
        
        waitForExpectations(timeout: 10.0)
    }
    
    func testCloudKitContainerAccess() {
        let container = CKContainer.default()
        XCTAssertNotNil(container, "CloudKit container should be accessible")
        
        let database = container.privateCloudDatabase
        XCTAssertNotNil(database, "Private database should be accessible")
    }
}
```

### 测试5: 文件导入功能测试

创建基础的文件导入测试：

```swift
import XCTest
import UniformTypeIdentifiers
@testable import IslaBooks

class FileImportTests: XCTestCase {
    
    func testSupportedFileTypes() {
        let epubType = UTType.epub
        XCTAssertNotNil(epubType, "EPUB type should be supported")
        
        let textType = UTType.plainText
        XCTAssertNotNil(textType, "Plain text type should be supported")
    }
    
    func testDocumentPickerConfiguration() {
        let supportedTypes = [UTType.epub, UTType.plainText]
        XCTAssertEqual(supportedTypes.count, 2, "Should support 2 file types")
    }
}
```

### 测试6: UI组件测试

创建UI测试：

```swift
import XCTest
@testable import IslaBooks

class IslaBooks_UITests: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    func testAppLaunch() throws {
        let app = XCUIApplication()
        app.launch()
        
        // 验证应用成功启动
        XCTAssertTrue(app.state == .runningForeground)
    }
    
    func testMainTabNavigation() throws {
        let app = XCUIApplication()
        app.launch()
        
        // 测试标签栏导航
        if app.tabBars.exists {
            let tabBar = app.tabBars.firstMatch
            XCTAssertTrue(tabBar.exists)
        }
    }
}
```

### 运行完整测试套件

```bash
# 运行所有测试
xcodebuild test -project IslaBooks.xcodeproj -scheme IslaBooks -destination 'platform=iOS Simulator,name=iPhone 15' -resultBundlePath TestResults

# 查看测试结果
open TestResults.xcresult
```

---

## 🔧 第七步：开发工具配置

### SwiftLint代码规范检查

1. **安装SwiftLint**
   ```bash
   # 使用Homebrew安装
   brew install swiftlint
   
   # 验证安装
   swiftlint version
   ```

2. **配置Build Phase**
   - 在Xcode项目中选择Target
   - Build Phases → + → New Run Script Phase
   - 添加脚本：
   ```bash
   if which swiftlint >/dev/null; then
     swiftlint
   else
     echo "warning: SwiftLint not installed, download from https://github.com/realm/SwiftLint"
   fi
   ```

3. **创建.swiftlint.yml配置文件**
   ```yaml
   disabled_rules:
     - trailing_whitespace
   opt_in_rules:
     - empty_count
     - empty_string
   included:
     - IslaBooks
   excluded:
     - Carthage
     - Pods
   line_length: 120
   ```

### Git配置

```bash
# 配置Git（如果还没有配置）
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"

# 在项目根目录初始化Git（如果还没有）
cd ~/Desktop/workspace/code/SelfProject/IslaProject/IslaBooks
git init
git add .
git commit -m "Initial project setup"

# 创建.gitignore文件
cat > .gitignore << EOF
# Xcode
*.xcodeproj/*
!*.xcodeproj/project.pbxproj
!*.xcodeproj/xcshareddata/
!*.xcworkspace/contents.xcworkspacedata
/*.gcno
**/xcshareddata/WorkspaceSettings.xcsettings

# Build generated
build/
DerivedData/

# Various settings
*.pbxuser
!default.pbxuser
*.mode1v3
!default.mode1v3
*.mode2v3
!default.mode2v3
*.perspectivev3
!default.perspectivev3
xcuserdata/

# CocoaPods
Pods/

# Carthage
Carthage/Build/

# SwiftPM
.swiftpm/

# macOS
.DS_Store
EOF
```

---

## 🚨 常见问题解决

### 问题1: Xcode安装失败
```bash
# 症状：App Store下载卡住或失败
# 解决方案：
1. 检查网络连接
2. 清理App Store缓存：
   sudo rm -rf ~/Library/Caches/com.apple.appstore
3. 重启Mac后重新下载
4. 考虑使用开发者网站下载
```

### 问题2: 证书配置错误
```
# 症状：Code signing error
# 解决方案：
1. 检查Bundle Identifier是否唯一
2. 在Xcode Preferences中重新登录Apple ID
3. 删除并重新创建开发证书
4. 确保Team选择正确
```

### 问题3: CloudKit配置问题
```
# 症状：CloudKit container找不到
# 解决方案：
1. 确保Container ID匹配Bundle Identifier
2. 检查CloudKit Dashboard中容器状态
3. 确保Capabilities中CloudKit已启用
4. 重启Xcode并重新配置
```

### 问题4: 模拟器启动问题
```bash
# 症状：模拟器无法启动或运行缓慢
# 解决方案：
# 重置模拟器
xcrun simctl erase all

# 重启模拟器服务
sudo killall -9 com.apple.CoreSimulator.CoreSimulatorService

# 检查可用内存
vm_stat
```

### 问题5: 依赖包下载失败
```
# 症状：Swift Package Manager下载失败
# 解决方案：
1. 检查网络连接
2. 清理Package缓存：
   rm -rf ~/Library/Caches/org.swift.swiftpm
3. 重置Package Dependencies：
   File → Package Dependencies → Reset Package Caches
```

---

## ✅ 验收清单

完成以下所有项目后，开发环境即配置成功：

### 基础环境
- [ ] macOS版本 ≥ 13.0
- [ ] Xcode 15+ 安装成功
- [ ] 命令行工具安装成功
- [ ] Apple ID配置完成

### 项目配置
- [ ] iOS项目创建成功
- [ ] Core Data集成完成
- [ ] CloudKit配置完成
- [ ] Info.plist权限配置完成
- [ ] Capabilities配置完成

### 依赖管理
- [ ] Swift Package Dependencies添加成功
- [ ] ZIPFoundation导入成功
- [ ] 项目编译无错误

### 测试验证
- [ ] 基础编译测试通过
- [ ] 模拟器运行测试通过
- [ ] Core Data测试通过
- [ ] CloudKit连接测试通过
- [ ] 单元测试运行成功
- [ ] UI测试运行成功

### 开发工具
- [ ] SwiftLint配置完成
- [ ] Git配置完成
- [ ] .gitignore文件创建

---

## 🎯 下一步开发计划

环境搭建完成后，可以开始以下开发工作：

1. **基础数据模型实现** (1-2天)
   - 完善Core Data模型
   - 实现基础的CRUD操作

2. **文件导入功能** (2-3天)
   - 实现文档选择器
   - ePub文件解析
   - 基础的书籍管理

3. **简单阅读器** (3-5天)
   - 文本渲染
   - 翻页功能
   - 基础阅读体验

4. **AI集成准备** (1-2天)
   - API客户端框架
   - 上下文构建基础

需要开始哪个具体功能的开发吗？我可以提供更详细的实现指导。

---

**预计总时间**: 2-4小时（取决于网络速度和硬件性能）
**难度级别**: 初级到中级
**完成标志**: 所有测试通过，应用能在模拟器中正常运行
