//
//  ReaderWebView.swift
//  LanRead
//
//  Created by AI Assistant on 2025/10/27.
//

import SwiftUI
import WebKit

struct SelectedTextInfo: Equatable {
    let text: String
    let startOffset: Int
    let endOffset: Int
    let rect: CGRect
    let pageIndex: Int
}

struct HighlightTapInfo: Equatable {
    let id: UUID
    let text: String
}

struct ReaderHighlight: Identifiable, Equatable {
    let id: UUID
    let startOffset: Int
    let endOffset: Int
    let colorHex: String
}

struct ReaderSelectionAction: Identifiable, Equatable {
    enum ActionType: Equatable {
        case highlight(colorHex: String)
    }

    let id = UUID()
    let type: ActionType
}

// MARK: - WebView Coordinator
class WebViewCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, UIScrollViewDelegate {
    var parent: ReaderWebView
    private var didApplyPagination = false
    weak var webView: WKWebView?
    weak var containerView: UIView?
    private var isAnimatingSlide = false
    private var pendingPageIndex: Int?
    private var isLoaded = false
    private var lastDisplayedPageIndex: Int = 0
    private var pendingHighlights: [ReaderHighlight] = []
    private var isTouchingContent = false
    
    init(_ parent: ReaderWebView) {
        self.parent = parent
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        applyPagination(on: webView)
        isLoaded = true
        lastDisplayedPageIndex = parent.currentPageIndex
        scrollToCurrentPage(on: webView, animated: false)
        parent.onLoadFinished?()
        applyHighlightsIfReady(on: webView)
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "toggleToolbar" {
            parent.onToolbarToggle?()
        } else if message.name == "interaction" {
            if let dict = message.body as? [String: Any],
               let active = dict["active"] as? Bool {
                handleInteractionChange(isActive: active)
            } else if let active = message.body as? Bool {
                handleInteractionChange(isActive: active)
            }
        } else if message.name == "textSelection" {
            if let dict = message.body as? [String: Any],
               let text = dict["text"] as? String {
                let start = dict["start"] as? Int ?? 0
                let end = dict["end"] as? Int ?? start
                let pageIndex = dict["pageIndex"] as? Int ?? 0
                let rect: CGRect
                if let rectDict = dict["rect"] as? [String: Double] {
                    let x = rectDict["x"] ?? 0
                    let y = rectDict["y"] ?? 0
                    let width = rectDict["width"] ?? 0
                    let height = rectDict["height"] ?? 0
                    rect = CGRect(x: x, y: y, width: width, height: height)
                } else {
                    rect = .zero
                }
                parent.onTextSelection?(
                    SelectedTextInfo(
                        text: text,
                        startOffset: start,
                        endOffset: end,
                        rect: rect,
                        pageIndex: pageIndex
                    )
                )
            } else if let text = message.body as? String {
                parent.onTextSelection?(
                    SelectedTextInfo(
                        text: text,
                        startOffset: 0,
                        endOffset: 0,
                        rect: .zero,
                        pageIndex: 0
                    )
                )
            }
        } else if message.name == "highlightTap" {
            if let dict = message.body as? [String: Any],
               let idString = dict["id"] as? String,
               let uuid = UUID(uuidString: idString) {
                let text = (dict["text"] as? String) ?? ""
                parent.onHighlightTap?(
                    HighlightTapInfo(id: uuid, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
                )
            }
        } else if message.name == "pageMetrics" {
            if let dict = message.body as? [String: Any] {
                if let type = dict["type"] as? String, type == "pageCount", let value = dict["value"] as? Int {
                    parent.totalPages = value
                }
            } else if let pages = message.body as? Int {
                parent.totalPages = pages
            }
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        // Scrolling is disabled; no-op
    }
    
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        // Scrolling is disabled; no-op
    }
    
    private func handleInteractionChange(isActive: Bool) {
        guard isTouchingContent != isActive else { return }
        isTouchingContent = isActive
        parent.onInteractionChange?(isActive)
        if !isActive, let webView {
            scrollToCurrentPage(on: webView, animated: false)
        }
    }
    
    private func applyPagination(on webView: WKWebView) {
        guard !didApplyPagination else { return }
        didApplyPagination = true
        let js = "applyPagination()"
        webView.evaluateJavaScript(js) { [weak self] _, _ in
            guard let self = self else { return }
            self.scrollToCurrentPage(on: webView, animated: false)
        }
    }
    
    func scrollToCurrentPage(on webView: WKWebView, animated: Bool = false) {
        let page = max(0, min(parent.currentPageIndex, max(parent.totalPages - 1, 0)))
        // Always perform JS jump without animation; we animate natively for smoothness
        let js = "scrollToPage(\(page), false)"
        webView.evaluateJavaScript(js, completionHandler: nil)
        // Native fallback to ensure position updates even if JS scrolling is ignored
        let applyOffset = {
            let pageWidth = webView.scrollView.bounds.width
            guard pageWidth > 0 else { return }
            let targetX = CGFloat(page) * pageWidth
            webView.scrollView.setContentOffset(CGPoint(x: targetX, y: 0), animated: animated)
        }
        if Thread.isMainThread {
            applyOffset()
        } else {
            DispatchQueue.main.async(execute: applyOffset)
        }
    }

    // Animate to the latest SwiftUI-bound page if it differs from what is currently displayed
    @discardableResult
    func animateToCurrentPageIfChanged(on webView: WKWebView) -> Bool {
        if isTouchingContent {
            return true
        }
        let newIndex = max(0, min(parent.currentPageIndex, max(parent.totalPages - 1, 0)))
        guard newIndex != lastDisplayedPageIndex else { return false }
        
        // If content is not ready yet, snap without animation to avoid blank states
        guard isLoaded else {
            lastDisplayedPageIndex = newIndex
            scrollToCurrentPage(on: webView, animated: false)
            return true
        }
        
        // If an animation is in-flight, queue the latest target and exit
        if isAnimatingSlide {
            pendingPageIndex = newIndex
            return true
        }
        
        performSlideTransition(to: newIndex, on: webView)
        return true
    }
    
    // MARK: - Lightweight page-turn animation
    private func performSlideTransition(to newIndex: Int, on webView: WKWebView) {
        guard let container = containerView else {
            scrollToCurrentPage(on: webView, animated: true)
            lastDisplayedPageIndex = newIndex
            return
        }

        let bounds = container.bounds
        guard bounds.width > 0 else {
            scrollToCurrentPage(on: webView, animated: false)
            lastDisplayedPageIndex = newIndex
            return
        }

        isAnimatingSlide = true

        // 使用轻量级的动画：直接通过 scrollView 的原生动画
        let pageWidth = bounds.width
        let targetOffset = CGFloat(newIndex) * pageWidth

        // 使用 CATransaction 实现更流畅的动画
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        CATransaction.setCompletionBlock { [weak self] in
            guard let self = self else { return }
            self.lastDisplayedPageIndex = newIndex
            self.isAnimatingSlide = false

            if let pending = self.pendingPageIndex, pending != newIndex {
                self.pendingPageIndex = nil
                self.performSlideTransition(to: pending, on: webView)
            } else {
                self.pendingPageIndex = nil
                // 确保最终位置准确
                self.scrollToCurrentPage(on: webView, animated: false)
            }
        }

        // 直接设置 scrollView 的 contentOffset
        webView.scrollView.setContentOffset(CGPoint(x: targetOffset, y: 0), animated: true)

        CATransaction.commit()
    }

    // Sync latest SwiftUI state to coordinator
    func updateParent(_ newParent: ReaderWebView) {
        self.parent = newParent
    }

    // Reset flags when reloading HTML content
    func prepareForNewLoad() {
        self.didApplyPagination = false
        self.isLoaded = false
        self.isAnimatingSlide = false
        self.pendingPageIndex = nil
        if isTouchingContent {
            isTouchingContent = false
            parent.onInteractionChange?(false)
        }
    }

    func updateHighlights(_ highlights: [ReaderHighlight]) {
        pendingHighlights = highlights
        applyHighlightsIfReady(on: webView)
    }

    func performSelectionAction(_ action: ReaderSelectionAction, on webView: WKWebView) {
        switch action.type {
        case .highlight(let colorHex):
            let safeColor = colorHex.replacingOccurrences(of: "'", with: "\\'")
            let js = "applyHighlightForSelection('\(safeColor)')"
            webView.evaluateJavaScript(js) { _, error in
                if let error {
                    DebugLogger.error("ReaderWebView: 高亮失败 - \(error.localizedDescription)")
                }
            }
        }
    }

    private func applyHighlightsIfReady(on webView: WKWebView?) {
        guard let webView, isLoaded else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: pendingHighlights.map { highlight in
            [
                "id": highlight.id.uuidString,
                "start": highlight.startOffset,
                "end": highlight.endOffset,
                "colorHex": highlight.colorHex
            ]
        }, options: []) else {
            return
        }

        guard let jsonString = String(data: data, encoding: .utf8) else { return }
        let js = "applyNativeHighlights(\(jsonString))"
        webView.evaluateJavaScript(js) { _, error in
            if let error {
                DebugLogger.error("ReaderWebView: 同步高亮失败 - \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Reader WebView
struct ReaderWebView: UIViewRepresentable {
    let htmlContent: String
    let appSettings: AppSettings
    let isDarkMode: Bool
    @Binding var currentPageIndex: Int
    @Binding var totalPages: Int
    @Binding var selectionAction: ReaderSelectionAction?
    var highlights: [ReaderHighlight]
    
    var onToolbarToggle: (() -> Void)?
    var onTextSelection: ((SelectedTextInfo) -> Void)?
    var onHighlightTap: ((HighlightTapInfo) -> Void)?
    var onLoadFinished: (() -> Void)?
    var onInteractionChange: ((Bool) -> Void)?
    
    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(self)
    }
    
    func makeUIView(context: Context) -> UIView {
        let configuration = WKWebViewConfiguration()
        
        // 配置用户脚本
        let userContentController = WKUserContentController()
        
        // 添加消息处理器
        userContentController.add(context.coordinator, name: "toggleToolbar")
        userContentController.add(context.coordinator, name: "textSelection")
        userContentController.add(context.coordinator, name: "highlightTap")
        userContentController.add(context.coordinator, name: "pageMetrics")
        userContentController.add(context.coordinator, name: "interaction")
        
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
        
        let container = UIView()
        container.backgroundColor = .clear
        container.clipsToBounds = true
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isPagingEnabled = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.alwaysBounceVertical = false
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.bounces = false
        webView.scrollView.isDirectionalLockEnabled = true
        webView.scrollView.delegate = context.coordinator
        // 仅允许编程式滚动，完全禁用用户滑动翻页
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        
        context.coordinator.webView = webView
        context.coordinator.containerView = container
        // 注释掉滑动手势，让ReaderView完全控制翻页
        // context.coordinator.attachSwipeGestures(to: container)
        
        return container
    }
    
    func updateUIView(_ container: UIView, context: Context) {
        guard let webView = context.coordinator.webView else { return }
        // Sync latest SwiftUI state to coordinator
        context.coordinator.updateParent(self)
        context.coordinator.updateHighlights(highlights)
        // Compute a signature that represents the visual content (chapter html + typography settings + theme)
        let signature = "sig::\(htmlContent.hashValue):\(appSettings.readingFontSize.fontSize):\(appSettings.lineSpacing):\(isDarkMode ? "dark" : "light"):\(Int(appSettings.pageMargins))"
        if container.accessibilityHint != signature {
            container.accessibilityHint = signature
            let html = generateFullHTML()
            context.coordinator.prepareForNewLoad()
            webView.loadHTMLString(html, baseURL: nil)
        } else {
            // 内容未重载：若页码变化则执行滑动动画；若未变化则确保位置同步
            let animated = context.coordinator.animateToCurrentPageIfChanged(on: webView)
            if !animated {
                context.coordinator.scrollToCurrentPage(on: webView, animated: false)
            }
        }

        if let action = selectionAction {
            context.coordinator.performSelectionAction(action, on: webView)
            DispatchQueue.main.async {
                self.selectionAction = nil
            }
        }
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
        let pageMargin = Int(appSettings.pageMargins)
        
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
            overflow-x: auto; /* 允许横向滚动 */
            overflow-y: hidden; /* 禁用纵向滚动 */
            background-color: \(backgroundColor);
            color: \(textColor);
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'PingFang SC', 'Hiragino Sans GB', 'Microsoft YaHei', sans-serif;
            -webkit-font-smoothing: antialiased;
            -moz-osx-font-smoothing: grayscale;
            text-size-adjust: 100%;
            -webkit-text-size-adjust: 100%;
            -webkit-overflow-scrolling: touch;
        }
        
        body {
            font-size: \(Int(fontSize))px;
            line-height: \(lineHeight);
            margin: 0;
            width: 100vw;
            height: 100vh; /* 每列高度 = 视口高度，WebView已经为页码预留了空间 */
            /* 将外侧留白移动到内容容器，避免根元素特殊滚动行为导致末页无右侧留白 */
            padding: 0; 
        }

        /* 主内容容器启用分栏以实现横向分页 */
        .reader-content {
            max-width: 100%;
            height: 100%;
            margin: 0;
            padding: 0;
            word-wrap: break-word;
            overflow-wrap: break-word;
            word-break: break-word;
            /* 分栏实现横向分页：每页宽度 = 100vw */
            -webkit-column-width: 100vw;
            column-width: 100vw;
            -webkit-column-gap: 0;
            column-gap: 0;
            -webkit-column-fill: auto;
            column-fill: auto;
        }
        
        /* 为所有内容元素添加左右边距，确保文字不会贴到屏幕边缘 */
        .reader-content * {
            padding-left: \(pageMargin)px !important;
            padding-right: \(pageMargin)px !important;
            box-sizing: border-box;
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

        mark.reader-highlight {
            background-color: \(isDarkMode ? "#3d2e12" : "#fff4b3");
            border-radius: 3px;
            padding: 0 2px;
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
        function normalizeColor(colorHex) {
            if (!colorHex) return '#ffe38f';
            if (colorHex.startsWith('#')) { return colorHex; }
            return '#' + colorHex;
        }
        
        var lastInteractionState = false;
        function notifyInteraction(active) {
            if (lastInteractionState === active) { return; }
            lastInteractionState = active;
            try { window.webkit.messageHandlers.interaction.postMessage({ active: !!active }); } catch (e) {}
        }

        function measureOffset(container, offset) {
            try {
                const preRange = document.createRange();
                preRange.selectNodeContents(document.body);
                preRange.setEnd(container, offset);
                const text = preRange.cloneContents().textContent || '';
                return text.length;
            } catch (e) {
                return 0;
            }
        }

        function serializeSelection() {
            const selection = window.getSelection();
            if (!selection || selection.rangeCount === 0) {
                return null;
            }

            const text = selection.toString();
            const range = selection.getRangeAt(0);
            const rect = range.getBoundingClientRect();
            const start = measureOffset(range.startContainer, range.startOffset);
            const end = measureOffset(range.endContainer, range.endOffset);
            const safeStart = Math.min(start, end);
            const safeEnd = Math.max(start, end);
            const pageIndex = Math.max(0, Math.round(getScrollLeft() / getPerPage()));

            return {
                text: text,
                start: safeStart,
                end: safeEnd,
                pageIndex: pageIndex,
                rect: {
                    x: rect.x,
                    y: rect.y,
                    width: rect.width,
                    height: rect.height
                }
            };
        }

        function notifySelectionChange() {
            const payload = serializeSelection();
            try {
                if (payload) {
                    window.webkit.messageHandlers.textSelection.postMessage(payload);
                } else {
                    window.webkit.messageHandlers.textSelection.postMessage({
                        text: "",
                        start: 0,
                        end: 0,
                        pageIndex: 0,
                        rect: { x: 0, y: 0, width: 0, height: 0 }
                    });
                }
            } catch (e) {}
        }

        // 文本选择处理
        document.addEventListener('selectionchange', notifySelectionChange);
        document.addEventListener('touchstart', function(){ notifyInteraction(true); }, { passive: true });
        document.addEventListener('touchend', function(){ notifyInteraction(false); }, { passive: true });
        document.addEventListener('touchcancel', function(){ notifyInteraction(false); }, { passive: true });
        
        // 防止双击缩放
        var lastTouchEnd = 0;
        document.addEventListener('touchend', function(event) {
            const now = Date.now();
            if (now - lastTouchEnd <= 300) {
                event.preventDefault();
            }
            lastTouchEnd = now;
        }, false);
        
        // 分页相关
        function getPerPage() {
            // 与CSS设置一致：每页宽度等于100vw
            return Math.max(1, window.innerWidth || document.documentElement.clientWidth || document.body.clientWidth || 1);
        }

        function getScrollLeft() {
            return (window.scrollX || document.documentElement.scrollLeft || document.body.scrollLeft || 0);
        }

        function getTotalWidth() {
            return Math.max(document.documentElement.scrollWidth, document.body.scrollWidth);
        }

        function updateEdgeOverlay() {
            try {
                var overlay = document.querySelector('.viewport-edge-right');
                if (!overlay) return;
                const perPage = getPerPage();
                const totalWidth = getTotalWidth();
                const x = getScrollLeft();
                const atLast = (x + perPage) >= (totalWidth - 1);
                overlay.style.display = atLast ? 'block' : 'none';
            } catch (e) {}
        }

        function computePageCount() {
            const totalWidth = getTotalWidth();
            const perPage = getPerPage();
            const pages = Math.max(1, Math.ceil(totalWidth / perPage));
            try { window.webkit.messageHandlers.pageMetrics.postMessage({ type: 'pageCount', value: pages }); } catch (e) {}
            updateEdgeOverlay();
            return pages;
        }
        
        function applyPagination() {
            // 启用横向滚动，禁用纵向滚动
            document.documentElement.style.overflowX = 'auto';
            document.documentElement.style.overflowY = 'hidden';
            document.body.style.overflowX = 'auto';
            document.body.style.overflowY = 'hidden';
            // 重新计算页数
            setTimeout(function(){ computePageCount(); updateEdgeOverlay(); }, 0);
        }
        
        function setScrollLeft(x, animated) {
            // 直接针对窗口滚动（与CSS overflow: auto 设置一致）
            try {
                if (animated) {
                    window.scrollTo({ left: x, top: 0, behavior: 'smooth' });
                } else {
                    window.scrollTo(x, 0);
                }
            } catch (e) {}
            // 兜底设置常见滚动宿主
            try { if (!animated && document.scrollingElement) { document.scrollingElement.scrollLeft = x; document.scrollingElement.scrollTop = 0; } } catch (e) {}
            try { if (!animated && document.documentElement) { document.documentElement.scrollLeft = x; document.documentElement.scrollTop = 0; } } catch (e) {}
            try { if (!animated && document.body) { document.body.scrollLeft = x; document.body.scrollTop = 0; } } catch (e) {}
            // 更新右缘覆盖层显示状态
            if (animated) {
                setTimeout(updateEdgeOverlay, 360);
            } else {
                updateEdgeOverlay();
            }
        }

        function scrollToPage(index, animated) {
            const perPage = getPerPage();
            const x = Math.max(0, Math.floor(index) * perPage);
            setScrollLeft(x, animated);
        }
        
        window.addEventListener('load', function() {
            applyPagination();
            // 初始跳转到指定页（若宿主设置了）
            try { window.webkit.messageHandlers.pageMetrics.postMessage({ type: 'pageCount', value: computePageCount() }); } catch (e) {}
            updateEdgeOverlay();
        });
        
        window.addEventListener('scroll', function(){ updateEdgeOverlay(); }, { passive: true });
        
        // 使用轻量防抖避免图片等资源异步加载时频繁重排导致的闪动
        var resizeTimer = null;
        function handleResize() {
            const perPage = getPerPage();
            const currentScroll = getScrollLeft();
            const currentPage = Math.round(currentScroll / Math.max(perPage, 1));
            
            if (resizeTimer) {
                clearTimeout(resizeTimer);
            }
            
            resizeTimer = setTimeout(function() {
                applyPagination();
                scrollToPage(currentPage, false);
                resizeTimer = null;
            }, 120);
        }
        
        window.addEventListener('resize', handleResize);

        // 高亮：选区内包裹 mark
        function applyHighlightForSelection(colorHex) {
            const selection = window.getSelection();
            if (!selection || selection.rangeCount === 0 || !selection.toString()) {
                return false;
            }
            const range = selection.getRangeAt(0);
            const wrapper = document.createElement('mark');
            wrapper.className = 'reader-highlight';
            wrapper.style.backgroundColor = normalizeColor(colorHex);

            try {
                const extracted = range.extractContents();
                wrapper.appendChild(extracted);
                range.insertNode(wrapper);
                selection.removeAllRanges();
                selection.addRange(range);
            } catch (e) {
                console.error('applyHighlightForSelection error', e);
                return false;
            }
            return true;
        }

        function clearExistingHighlights() {
            const marks = document.querySelectorAll('mark.reader-highlight');
            marks.forEach(mark => {
                const parent = mark.parentNode;
                while (mark.firstChild) {
                    parent.insertBefore(mark.firstChild, mark);
                }
                parent.removeChild(mark);
                if (parent.normalize) {
                    parent.normalize();
                }
            });
        }

        function highlightByOffsets(start, end, colorHex, highlightId) {
            if (typeof start !== 'number' || typeof end !== 'number' || start >= end) { return; }
            const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
            let current = 0;
            let rangeStartNode = null;
            let rangeStartOffset = 0;
            let rangeEndNode = null;
            let rangeEndOffset = 0;
            let node;

            while ((node = walker.nextNode())) {
                const textLength = (node.textContent || '').length;
                const nodeStart = current;
                const nodeEnd = current + textLength;

                if (!rangeStartNode && start >= nodeStart && start <= nodeEnd) {
                    rangeStartNode = node;
                    rangeStartOffset = start - nodeStart;
                }

                if (!rangeEndNode && end >= nodeStart && end <= nodeEnd) {
                    rangeEndNode = node;
                    rangeEndOffset = end - nodeStart;
                    break;
                }

                current = nodeEnd;
            }

            if (!rangeStartNode || !rangeEndNode) { return; }

            const range = document.createRange();
            range.setStart(rangeStartNode, rangeStartOffset);
            range.setEnd(rangeEndNode, rangeEndOffset);

            const wrapper = document.createElement('mark');
            wrapper.className = 'reader-highlight';
            if (highlightId) {
                wrapper.dataset.highlightId = highlightId;
            }
            wrapper.style.backgroundColor = normalizeColor(colorHex);

            wrapper.appendChild(range.extractContents());
            range.insertNode(wrapper);
            range.detach();
        }

        function applyNativeHighlights(items) {
            clearExistingHighlights();
            if (!items || !Array.isArray(items)) { return; }
            items.forEach(item => {
                highlightByOffsets(item.start, item.end, item.colorHex || '#ffe38f', item.id || '');
            });
        }

        var highlightTapBound = false;
        function bindHighlightTapHandler() {
            if (highlightTapBound) { return; }
            document.addEventListener('click', function(event) {
                var node = event.target;
                var targetHighlight = null;
                while (node) {
                    if (node.classList && node.classList.contains('reader-highlight')) {
                        targetHighlight = node;
                        break;
                    }
                    node = node.parentElement;
                }
                if (!targetHighlight) { return; }
                var highlightId = (targetHighlight.dataset && targetHighlight.dataset.highlightId) ? targetHighlight.dataset.highlightId : '';
                if (!highlightId) { return; }
                var text = targetHighlight.textContent || '';
                try { 
                    window.webkit.messageHandlers.highlightTap.postMessage({ id: highlightId, text: text });
                    if (event && event.preventDefault) { event.preventDefault(); }
                    if (window.getSelection) {
                        var selection = window.getSelection();
                        if (selection && selection.removeAllRanges) {
                            selection.removeAllRanges();
                        }
                    }
                } catch (e) {}
            }, true);
            highlightTapBound = true;
        }

        bindHighlightTapHandler();
        """
    }
}
