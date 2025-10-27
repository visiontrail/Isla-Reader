//
//  ReaderWebView.swift
//  Isla Reader
//
//  Created by AI Assistant on 2025/10/27.
//

import SwiftUI
import WebKit

// MARK: - WebView Coordinator
class WebViewCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var parent: ReaderWebView
    
    init(_ parent: ReaderWebView) {
        self.parent = parent
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        parent.onLoadFinished?()
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "toggleToolbar" {
            parent.onToolbarToggle?()
        } else if message.name == "textSelection", let text = message.body as? String {
            parent.onTextSelected?(text)
        }
    }
}

// MARK: - Reader WebView
struct ReaderWebView: UIViewRepresentable {
    let htmlContent: String
    let appSettings: AppSettings
    let isDarkMode: Bool
    
    var onToolbarToggle: (() -> Void)?
    var onTextSelected: ((String) -> Void)?
    var onLoadFinished: (() -> Void)?
    
    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        
        // 配置用户脚本
        let userContentController = WKUserContentController()
        
        // 添加消息处理器
        userContentController.add(context.coordinator, name: "toggleToolbar")
        userContentController.add(context.coordinator, name: "textSelection")
        
        // 添加JavaScript代码
        let script = WKUserScript(source: getJavaScriptCode(), injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        userContentController.addUserScript(script)
        
        configuration.userContentController = userContentController
        
        // 禁用缩放
        let source = """
        var meta = document.createElement('meta');
        meta.name = 'viewport';
        meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
        document.getElementsByTagName('head')[0].appendChild(meta);
        """
        let zoomScript = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        userContentController.addUserScript(zoomScript)
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        let fullHTML = generateFullHTML()
        webView.loadHTMLString(fullHTML, baseURL: nil)
    }
    
    private func generateFullHTML() -> String {
        let css = getMobileOptimizedCSS()
        
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                \(css)
            </style>
        </head>
        <body>
            <div class="reader-content">
                \(htmlContent)
            </div>
        </body>
        </html>
        """
    }
    
    private func getMobileOptimizedCSS() -> String {
        // 根据用户设置和主题生成CSS
        let fontSize = appSettings.readingFontSize.fontSize
        let lineHeight = 1.6 + (appSettings.lineSpacing * 0.2)
        let backgroundColor = isDarkMode ? "#0d0d12" : "#fafafa"
        let textColor = isDarkMode ? "rgba(255, 255, 255, 0.87)" : "rgba(0, 0, 0, 0.87)"
        let linkColor = isDarkMode ? "#64b5f6" : "#1976d2"
        
        return """
        /* 基础样式 - 移动端优化 */
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
            -webkit-tap-highlight-color: transparent;
        }
        
        html, body {
            width: 100%;
            height: 100%;
            overflow-x: hidden;
            background-color: \(backgroundColor);
            color: \(textColor);
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'PingFang SC', 'Hiragino Sans GB', 'Microsoft YaHei', sans-serif;
            -webkit-font-smoothing: antialiased;
            -moz-osx-font-smoothing: grayscale;
            text-size-adjust: 100%;
            -webkit-text-size-adjust: 100%;
        }
        
        body {
            font-size: \(Int(fontSize))px;
            line-height: \(lineHeight);
            padding: 0;
            margin: 0;
        }
        
        /* 主内容容器 */
        .reader-content {
            max-width: 100%;
            padding: 0;
            margin: 0 auto;
            word-wrap: break-word;
            overflow-wrap: break-word;
            word-break: break-word;
        }
        
        /* 段落样式 */
        p {
            margin: 0 0 1em 0;
            text-align: justify;
            text-indent: 2em;
        }
        
        /* 标题样式 */
        h1, h2, h3, h4, h5, h6 {
            font-weight: 600;
            margin: 1.5em 0 0.8em 0;
            line-height: 1.3;
            text-indent: 0;
        }
        
        h1 {
            font-size: 1.8em;
            border-bottom: 2px solid \(isDarkMode ? "#333" : "#e0e0e0");
            padding-bottom: 0.3em;
        }
        
        h2 {
            font-size: 1.5em;
        }
        
        h3 {
            font-size: 1.3em;
        }
        
        h4 {
            font-size: 1.1em;
        }
        
        h5, h6 {
            font-size: 1em;
        }
        
        /* 链接样式 */
        a {
            color: \(linkColor);
            text-decoration: none;
            word-break: break-all;
        }
        
        a:active {
            opacity: 0.7;
        }
        
        /* 图片样式 - 移动端优化 */
        img {
            max-width: 100% !important;
            height: auto !important;
            display: block;
            margin: 1em auto;
            border-radius: 4px;
        }
        
        /* 列表样式 */
        ul, ol {
            margin: 0.5em 0 0.5em 1.5em;
            padding-left: 1em;
        }
        
        li {
            margin: 0.3em 0;
        }
        
        /* 引用样式 */
        blockquote {
            margin: 1em 0;
            padding: 0.5em 1em;
            border-left: 4px solid \(isDarkMode ? "#555" : "#ddd");
            background-color: \(isDarkMode ? "#1a1a1a" : "#f5f5f5");
            font-style: italic;
        }
        
        /* 代码样式 */
        code {
            font-family: 'Menlo', 'Monaco', 'Courier New', monospace;
            font-size: 0.9em;
            padding: 0.2em 0.4em;
            background-color: \(isDarkMode ? "#1a1a1a" : "#f5f5f5");
            border-radius: 3px;
        }
        
        pre {
            margin: 1em 0;
            padding: 1em;
            background-color: \(isDarkMode ? "#1a1a1a" : "#f5f5f5");
            border-radius: 4px;
            overflow-x: auto;
            -webkit-overflow-scrolling: touch;
        }
        
        pre code {
            padding: 0;
            background-color: transparent;
        }
        
        /* 表格样式 - 移动端优化 */
        table {
            width: 100%;
            max-width: 100%;
            border-collapse: collapse;
            margin: 1em 0;
            display: block;
            overflow-x: auto;
            -webkit-overflow-scrolling: touch;
        }
        
        th, td {
            padding: 0.5em;
            border: 1px solid \(isDarkMode ? "#333" : "#ddd");
            text-align: left;
        }
        
        th {
            background-color: \(isDarkMode ? "#1a1a1a" : "#f5f5f5");
            font-weight: 600;
        }
        
        /* 水平线 */
        hr {
            border: none;
            border-top: 1px solid \(isDarkMode ? "#333" : "#ddd");
            margin: 2em 0;
        }
        
        /* 强调样式 */
        strong, b {
            font-weight: 600;
        }
        
        em, i {
            font-style: italic;
        }
        
        /* 删除线 */
        del, s {
            text-decoration: line-through;
        }
        
        /* 下划线 */
        u {
            text-decoration: underline;
        }
        
        /* 小号文字 */
        small {
            font-size: 0.85em;
        }
        
        /* 确保所有块级元素不超出屏幕 */
        div, article, section, aside, nav, header, footer, main {
            max-width: 100%;
            word-wrap: break-word;
        }
        
        /* 防止预格式化文本超出屏幕 */
        pre, code, kbd, samp {
            white-space: pre-wrap;
            word-wrap: break-word;
        }
        
        /* SVG 图片优化 */
        svg {
            max-width: 100%;
            height: auto;
        }
        
        /* 选中文本的样式 */
        ::selection {
            background-color: \(isDarkMode ? "#4a6fa5" : "#b3d4fc");
            color: \(isDarkMode ? "#fff" : "#000");
        }
        
        /* iframe 优化 */
        iframe {
            max-width: 100%;
        }
        
        /* 针对某些epub特定的类 */
        .pagebreak {
            page-break-after: always;
            margin: 2em 0;
        }
        
        /* 脚注样式 */
        .footnote {
            font-size: 0.85em;
            vertical-align: super;
        }
        
        /* 禁用用户选择某些元素（如果需要） */
        .no-select {
            -webkit-user-select: none;
            -moz-user-select: none;
            -ms-user-select: none;
            user-select: none;
        }
        """
    }
    
    private func getJavaScriptCode() -> String {
        return """
        // 点击处理
        let lastTapTime = 0;
        document.addEventListener('click', function(e) {
            const now = Date.now();
            if (now - lastTapTime < 300) {
                // 双击
                return;
            }
            lastTapTime = now;
            
            // 检查是否点击了链接
            if (e.target.tagName === 'A') {
                e.preventDefault();
                return;
            }
            
            // 单击切换工具栏
            window.webkit.messageHandlers.toggleToolbar.postMessage('toggle');
        });
        
        // 文本选择处理
        document.addEventListener('selectionchange', function() {
            const selection = window.getSelection();
            if (selection && selection.toString().length > 0) {
                window.webkit.messageHandlers.textSelection.postMessage(selection.toString());
            }
        });
        
        // 禁用长按菜单（可选）
        document.addEventListener('contextmenu', function(e) {
            e.preventDefault();
        });
        
        // 防止双击缩放
        let lastTouchEnd = 0;
        document.addEventListener('touchend', function(event) {
            const now = Date.now();
            if (now - lastTouchEnd <= 300) {
                event.preventDefault();
            }
            lastTouchEnd = now;
        }, false);
        """
    }
}

