//
//  MarkdownRenderer.swift
//  LanRead
//
//  Created by AI Assistant on 2025/1/20.
//

import SwiftUI
import Foundation

struct MarkdownTypography {
    let heading1: Font
    let heading2: Font
    let heading3: Font
    let bullet: Font
    let body: Font
    let bold: Font
    let italic: Font

    static let standard = MarkdownTypography(
        heading1: .title.bold(),
        heading2: .title2.bold(),
        heading3: .title3.bold(),
        bullet: .body.bold(),
        body: .body,
        bold: .body.bold(),
        italic: .body.italic()
    )

    static let shareCard = MarkdownTypography(
        heading1: .system(size: 46, weight: .bold, design: .rounded),
        heading2: .system(size: 42, weight: .bold, design: .rounded),
        heading3: .system(size: 38, weight: .bold, design: .rounded),
        bullet: .system(size: 36, weight: .semibold, design: .rounded),
        body: .system(size: 36, weight: .regular, design: .rounded),
        bold: .system(size: 36, weight: .bold, design: .rounded),
        italic: .system(size: 36, weight: .regular, design: .rounded).italic()
    )
}

/// Markdown渲染器，用于将markdown文本转换为格式化的AttributedString
struct MarkdownRenderer {
    
    /// 将markdown文本转换为AttributedString
    /// - Parameter markdown: 原始markdown文本
    /// - Returns: 格式化的AttributedString
    static func render(
        _ markdown: String,
        textColor: Color = .primary,
        typography: MarkdownTypography = .standard
    ) -> AttributedString {
        var attributedString = AttributedString()
        
        let lines = markdown.components(separatedBy: .newlines)
        
        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmedLine.isEmpty {
                // 空行，添加换行符
                if index < lines.count - 1 {
                    attributedString += AttributedString("\n")
                }
                continue
            }
            
            var lineAttributedString = AttributedString()
            
            // 处理不同的markdown格式
            if trimmedLine.hasPrefix("# ") {
                // 一级标题
                lineAttributedString = AttributedString(String(trimmedLine.dropFirst(2)))
                lineAttributedString.font = typography.heading1
                lineAttributedString.foregroundColor = textColor
            } else if trimmedLine.hasPrefix("## ") {
                // 二级标题
                lineAttributedString = AttributedString(String(trimmedLine.dropFirst(3)))
                lineAttributedString.font = typography.heading2
                lineAttributedString.foregroundColor = textColor
            } else if trimmedLine.hasPrefix("### ") {
                // 三级标题
                lineAttributedString = AttributedString(String(trimmedLine.dropFirst(4)))
                lineAttributedString.font = typography.heading3
                lineAttributedString.foregroundColor = textColor
            } else if trimmedLine.hasPrefix("• ") || trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") {
                // 列表项
                let bulletPoint = "• "
                let content = String(trimmedLine.dropFirst(2))
                
                var bulletString = AttributedString(bulletPoint)
                bulletString.foregroundColor = .blue
                bulletString.font = typography.bullet
                
                var contentString = AttributedString(content)
                contentString.font = typography.body
                contentString.foregroundColor = textColor
                
                lineAttributedString = bulletString + contentString
            } else if trimmedLine.contains("**") {
                // 处理粗体文本
                lineAttributedString = processBoldText(trimmedLine, textColor: textColor, typography: typography)
            } else if containsItalicMarkdown(trimmedLine) {
                // 处理斜体文本
                lineAttributedString = processItalicText(trimmedLine, textColor: textColor, typography: typography)
            } else {
                // 普通段落
                lineAttributedString = AttributedString(trimmedLine)
                lineAttributedString.font = typography.body
                lineAttributedString.foregroundColor = textColor
            }
            
            attributedString += lineAttributedString
            
            // 添加换行符（除了最后一行）
            if index < lines.count - 1 {
                attributedString += AttributedString("\n")
            }
        }
        
        return attributedString
    }
    
    /// 检查文本是否包含有效的斜体markdown标记
    private static func containsItalicMarkdown(_ text: String) -> Bool {
        // 排除列表项
        if text.hasPrefix("• ") || text.hasPrefix("- ") || text.hasPrefix("* ") {
            return false
        }
        
        // 检查是否包含成对的单星号（但不是双星号的一部分）
        let pattern = #"(?<!\*)\*(?!\*)([^*]+)(?<!\*)\*(?!\*)"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: text.utf16.count)
        return regex?.firstMatch(in: text, options: [], range: range) != nil
    }
    
    /// 处理粗体文本
    private static func processBoldText(
        _ text: String,
        textColor: Color,
        typography: MarkdownTypography
    ) -> AttributedString {
        var result = AttributedString()
        let components = text.components(separatedBy: "**")
        
        for (index, component) in components.enumerated() {
            var componentString = AttributedString(component)
            
            if index % 2 == 1 {
                // 奇数索引的组件是粗体
                componentString.font = typography.bold
            } else {
                componentString.font = typography.body
            }
            componentString.foregroundColor = textColor
            
            result += componentString
        }
        
        return result
    }
    
    /// 处理斜体文本
    private static func processItalicText(
        _ text: String,
        textColor: Color,
        typography: MarkdownTypography
    ) -> AttributedString {
        var result = AttributedString()
        
        // 使用正则表达式匹配成对的单星号
        let pattern = #"(?<!\*)\*(?!\*)([^*]+?)(?<!\*)\*(?!\*)"#
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: text.utf16.count)
        
        var lastEnd = 0
        let matches = regex.matches(in: text, options: [], range: range)
        
        for match in matches {
            // 添加匹配前的普通文本
            if match.range.location > lastEnd {
                let beforeRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                if let beforeText = Range(beforeRange, in: text) {
                    var beforeString = AttributedString(String(text[beforeText]))
                    beforeString.font = typography.body
                    beforeString.foregroundColor = textColor
                    result += beforeString
                }
            }
            
            // 添加斜体文本（不包括星号）
            if match.numberOfRanges > 1 {
                let italicRange = match.range(at: 1)
                if let italicText = Range(italicRange, in: text) {
                    var italicString = AttributedString(String(text[italicText]))
                    italicString.font = typography.italic
                    italicString.foregroundColor = textColor
                    result += italicString
                }
            }
            
            lastEnd = match.range.location + match.range.length
        }
        
        // 添加剩余的普通文本
        if lastEnd < text.count {
            let remainingRange = NSRange(location: lastEnd, length: text.count - lastEnd)
            if let remainingText = Range(remainingRange, in: text) {
                var remainingString = AttributedString(String(text[remainingText]))
                remainingString.font = typography.body
                remainingString.foregroundColor = textColor
                result += remainingString
            }
        }
        
        // 如果没有找到匹配项，返回原始文本
        if matches.isEmpty {
            var plainString = AttributedString(text)
            plainString.font = typography.body
            plainString.foregroundColor = textColor
            result = plainString
        }
        
        return result
    }
}

/// SwiftUI视图组件，用于显示markdown文本
struct MarkdownText: View {
    let markdown: String
    let lineSpacing: CGFloat
    let textColor: Color
    let typography: MarkdownTypography
    
    init(
        _ markdown: String,
        lineSpacing: CGFloat = 6,
        textColor: Color = .primary,
        typography: MarkdownTypography = .standard
    ) {
        self.markdown = markdown
        self.lineSpacing = lineSpacing
        self.textColor = textColor
        self.typography = typography
    }
    
    var body: some View {
        Text(MarkdownRenderer.render(markdown, textColor: textColor, typography: typography))
            .lineSpacing(lineSpacing)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        MarkdownText("""
        # 这是一级标题
        
        ## 这是二级标题
        
        这是一个普通段落，包含一些**粗体文本**和*斜体文本*。
        
        ### 关键要点：
        
        • 第一个要点
        • 第二个要点
        • 第三个要点
        
        - 另一种列表格式
        - 第二项
        * 第三种格式
        
        ### 测试单星号处理：
        
        这里有*正确的斜体*文本。
        这里有**粗体**和*斜体*混合。
        这里有单个*星号应该不被处理。
        这里有*多个* *斜体* *文本*。
        """)
        
        Spacer()
    }
    .padding()
}
