# AI摘要多语言支持文档

## 概述

本文档描述了如何为AI摘要功能实现多语言支持。AI摘要服务现在会根据用户设置的语言自动生成对应语言的prompt和响应。

## 支持的语言

- 🇨🇳 中文 (简体) - `zh-Hans`
- 🇺🇸 英语 - `en`
- 🇯🇵 日语 - `ja`
- 🇰🇷 韩语 - `ko`

## 实现细节

### 1. 本地化字符串

所有AI摘要相关的prompt文本都已添加到各个语言的`Localizable.strings`文件中：

#### 书籍摘要Prompt键

```
ai.summary.book.prompt.title           - 提示词标题
ai.summary.book.prompt.book_info       - "书籍信息"标签
ai.summary.book.prompt.content_excerpt - "书籍内容节选"标签
ai.summary.book.prompt.requirements    - "请生成"标题
ai.summary.book.prompt.requirement1    - 要求1：全书摘要
ai.summary.book.prompt.requirement2    - 要求2：关键要点
ai.summary.book.prompt.requirement3    - 要求3：简洁明了
ai.summary.book.prompt.format          - "格式要求"标题
ai.summary.book.prompt.format1         - 格式要求1：段落形式
ai.summary.book.prompt.format2         - 格式要求2：列表形式
```

#### 章节摘要Prompt键

```
ai.summary.chapter.prompt.title        - 提示词标题
ai.summary.chapter.prompt.chapter_title - "章节标题"标签
ai.summary.chapter.prompt.chapter_content - "章节内容"标签
ai.summary.chapter.prompt.requirements - "请生成"标题
ai.summary.chapter.prompt.requirement1 - 要求1：章节摘要
ai.summary.chapter.prompt.requirement2 - 要求2：关键要点
ai.summary.chapter.prompt.format       - 格式要求
```

#### 书籍信息标签

```
ai.summary.book_name     - "书名"/"Title"等
ai.summary.author        - "作者"/"Author"等
ai.summary.chapter_count - "章节数"/"Chapters"等
```

### 2. AISummaryService修改

#### `buildSummaryPrompt`方法

该方法现在使用`NSLocalizedString`来获取对应语言的prompt文本：

```swift
private func buildSummaryPrompt(book: Book, chapters: [Chapter]) -> String {
    // 获取本地化字符串
    let bookName = NSLocalizedString("ai.summary.book_name", comment: "")
    let author = NSLocalizedString("ai.summary.author", comment: "")
    // ... 更多本地化字符串
    
    // 构建prompt
    let prompt = """
    \(promptTitle)
    
    \(bookInfoLabel)
    \(bookInfo)
    
    \(contentExcerpt)
    \(content)
    
    \(requirements)
    \(requirement1)
    \(requirement2)
    \(requirement3)
    
    \(format)
    \(format1)
    \(format2)
    """
    
    return prompt
}
```

#### `buildChapterSummaryPrompt`方法

类似地，章节摘要prompt也使用本地化字符串：

```swift
private func buildChapterSummaryPrompt(chapter: Chapter) -> String {
    let promptTitle = NSLocalizedString("ai.summary.chapter.prompt.title", comment: "")
    let chapterTitle = NSLocalizedString("ai.summary.chapter.prompt.chapter_title", comment: "")
    // ... 更多本地化字符串
    
    let prompt = """
    \(promptTitle)
    
    \(chapterTitle) \(chapter.title)
    \(chapterContent) \(String(chapter.content.prefix(1000)))...
    
    \(requirements)
    \(requirement1)
    \(requirement2)
    
    \(format)
    """
    
    return prompt
}
```

#### `generateLocalizedMockResponse`方法

为模拟API响应添加了多语言支持：

```swift
private func generateLocalizedMockResponse() -> String {
    let currentLanguage = Locale.current.language.languageCode?.identifier ?? "en"
    
    switch currentLanguage {
    case "zh": return "中文模拟响应..."
    case "ja": return "日语模拟响应..."
    case "ko": return "韩语模拟响应..."
    default:   return "英语模拟响应..."
    }
}
```

## 使用方式

### 用户角度

1. 用户在设置中选择应用语言
2. 打开书籍查看AI摘要
3. AI会自动使用对应语言生成摘要

### 开发者角度

语言切换由系统自动处理：

1. `AppSettings.shared.language` 存储用户选择的语言
2. `Isla_ReaderApp` 设置环境的locale：`.environment(\.locale, appSettings.locale)`
3. `NSLocalizedString` 自动根据当前locale获取对应的本地化字符串

## 示例

### 中文Prompt示例

```
请为以下书籍生成一份导读摘要：

书籍信息：
书名：示例书籍
作者：示例作者
章节数：10

书籍内容节选：
【第一章】
内容...

请生成：
1. 一份200-300字的全书导读摘要，包含主要内容、核心观点和阅读价值
2. 3-5个关键要点
3. 简洁明了，适合快速了解书籍内容

格式要求：
- 摘要部分用自然段落形式
- 关键要点用"• "开头的列表形式
```

### 英文Prompt示例

```
Please generate a reading guide summary for the following book:

Book Information:
Title: Example Book
Author: Example Author
Chapters: 10

Book Content Excerpt:
【Chapter 1】
Content...

Please generate:
1. A 200-300 word book summary including main content, core ideas, and reading value
2. 3-5 key points
3. Clear and concise, suitable for quickly understanding the book content

Format requirements:
- Summary part in natural paragraph form
- Key points in list form starting with "• "
```

## 测试

### 测试步骤

1. 切换应用语言到中文
2. 导入一本书并生成AI摘要
3. 查看日志中的prompt是否为中文
4. 重复以上步骤测试英语、日语、韩语

### 日志输出

在DebugLogger中可以看到生成的prompt：

```
AISummaryService: === 提示词 (Prompt) 开始 ===
[对应语言的完整prompt]
AISummaryService: === 提示词 (Prompt) 结束 ===
```

## 扩展其他语言

要添加新语言支持，需要：

1. 在新语言的`Localizable.strings`文件中添加所有AI摘要相关的键
2. 在`AppLanguage`枚举中添加新语言
3. 在`generateLocalizedMockResponse`方法中添加对应的模拟响应

## 注意事项

1. **API调用**：当接入真实的AI API时，确保API支持多语言输入和输出
2. **Token计数**：不同语言的token计数方式可能不同，需要注意API的token限制
3. **响应解析**：不同语言的响应格式可能略有差异，需要确保解析逻辑足够健壮
4. **字符限制**：不同语言表达同样内容所需的字符数可能不同（中文vs英文）

## 未来改进

- [ ] 支持更多语言（法语、德语、西班牙语等）
- [ ] 优化不同语言的字符限制（如中文200字 vs 英文300词）
- [ ] 根据书籍原语言智能选择摘要语言
- [ ] 支持多语言并行生成
- [ ] 提供语言偏好的独立设置（独立于应用界面语言）

## 相关文件

- `Isla Reader/Utils/AISummaryService.swift` - AI摘要服务主文件
- `Isla Reader/en.lproj/Localizable.strings` - 英语本地化
- `Isla Reader/zh-Hans.lproj/Localizable.strings` - 简体中文本地化
- `Isla Reader/ja.lproj/Localizable.strings` - 日语本地化
- `Isla Reader/ko.lproj/Localizable.strings` - 韩语本地化
- `Isla Reader/Models/AppSettings.swift` - 应用设置模型

---

最后更新：2025年10月22日

