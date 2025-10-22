# AI Summary 动态本地化修复

## 问题描述

在之前的实现中，AI 摘要功能的提示词模板使用了 `NSLocalizedString` 来获取本地化字符串。但是 `NSLocalizedString` 默认使用的是应用启动时的系统语言设置，当用户在应用内切换语言后，提示词模板不会动态切换到对应的语言，导致发送给大模型的提示词始终保持原语言。

## 解决方案

### 1. 创建 LocalizationHelper 工具类

创建了 `LocalizationHelper.swift` 文件，提供动态本地化功能：

```swift
class LocalizationHelper {
    static func localizedString(_ key: String, comment: String = "") -> String {
        let appLanguage = AppSettings.shared.language
        
        // 如果选择跟随系统，使用默认的 NSLocalizedString
        if appLanguage == .system {
            return NSLocalizedString(key, comment: comment)
        }
        
        // 根据用户选择的语言，从对应的 .lproj 目录加载本地化字符串
        guard let bundlePath = Bundle.main.path(forResource: languageCode(for: appLanguage), ofType: "lproj"),
              let bundle = Bundle(path: bundlePath) else {
            return NSLocalizedString(key, comment: comment)
        }
        
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}
```

### 2. 更新 AISummaryService

将 `AISummaryService.swift` 中所有使用 `NSLocalizedString` 的地方替换为 `LocalizationHelper.localizedString`：

- `buildSummaryPrompt()` 方法 - 全书摘要提示词
- `buildChapterSummaryPrompt()` 方法 - 章节摘要提示词
- `generateLocalizedMockResponse()` 方法 - 模拟响应

### 3. 添加调试日志

在提示词构建方法中添加了语言设置的日志输出，方便调试：

```swift
DebugLogger.info("AISummaryService: 当前应用语言设置 = \(AppSettings.shared.language.rawValue)")
```

## 支持的语言

该修复支持以下语言的动态切换：

- **English** (`en`)
- **简体中文** (`zh-Hans`)  
- **日本語** (`ja`)
- **한국어** (`ko`)
- **跟随系统** (`system`)

## 测试方法

1. 打开应用，进入 **设置** -> **语言**
2. 选择一种语言（如：中文）
3. 打开一本书，点击生成 AI 摘要
4. 查看日志输出，确认提示词使用了正确的语言
5. 切换到另一种语言（如：English）
6. 重新生成摘要，确认提示词已切换到新语言

## 技术细节

### LocalizationHelper 工作原理

1. 从 `AppSettings.shared.language` 获取用户选择的语言
2. 如果是 `system`，使用系统默认的 `NSLocalizedString`
3. 否则，根据语言代码（如 `zh-Hans`）找到对应的 `.lproj` 目录
4. 从该目录的 `Localizable.strings` 文件中读取本地化字符串

### 与 NSLocalizedString 的区别

| 特性 | NSLocalizedString | LocalizationHelper |
|------|-------------------|-------------------|
| 语言来源 | 系统语言/应用启动时语言 | 用户在应用内选择的语言 |
| 动态切换 | ❌ 需要重启应用 | ✅ 实时响应 |
| 使用场景 | 静态 UI 文本 | 需要动态切换的内容 |

## 修改的文件

1. **新增文件**:
   - `Isla Reader/Utils/LocalizationHelper.swift`

2. **修改文件**:
   - `Isla Reader/Utils/AISummaryService.swift`
     - `buildSummaryPrompt()` 方法
     - `buildChapterSummaryPrompt()` 方法  
     - `generateLocalizedMockResponse()` 方法

## 本地化字符串键值

以下是 AI 摘要相关的本地化键值（已在所有语言的 `Localizable.strings` 中配置）：

### 全书摘要提示词
- `ai.summary.book.prompt.title`
- `ai.summary.book.prompt.book_info`
- `ai.summary.book.prompt.content_excerpt`
- `ai.summary.book.prompt.requirements`
- `ai.summary.book.prompt.requirement1`
- `ai.summary.book.prompt.requirement2`
- `ai.summary.book.prompt.requirement3`
- `ai.summary.book.prompt.format`
- `ai.summary.book.prompt.format1`
- `ai.summary.book.prompt.format2`
- `ai.summary.book.prompt.language`

### 章节摘要提示词
- `ai.summary.chapter.prompt.title`
- `ai.summary.chapter.prompt.chapter_title`
- `ai.summary.chapter.prompt.chapter_content`
- `ai.summary.chapter.prompt.requirements`
- `ai.summary.chapter.prompt.requirement1`
- `ai.summary.chapter.prompt.requirement2`
- `ai.summary.chapter.prompt.format`
- `ai.summary.chapter.prompt.language`

### 书籍信息
- `ai.summary.book_name`
- `ai.summary.author`
- `ai.summary.chapter_count`

## 后续建议

1. **性能优化**: 考虑缓存 Bundle 对象，避免重复加载
2. **错误处理**: 添加更完善的错误处理和降级策略
3. **扩展性**: 可以将 `LocalizationHelper` 扩展为全局使用，替代所有需要动态切换的 `NSLocalizedString`

## 参考

- [Apple Documentation: NSLocalizedString](https://developer.apple.com/documentation/foundation/nslocalizedstring)
- [iOS Localization Guide](https://developer.apple.com/localization/)

