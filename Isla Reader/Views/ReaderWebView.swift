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

// MARK: - Page Turn Animation Style
enum PageTurnAnimationStyle {
    case fade   // Tap-based: instant jump + crossfade (120-150ms)
    case slide  // Swipe-based: horizontal scroll animation
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
    private var isResolvingInteractionPage = false
    private var lastAppliedTOCNavigationToken: Int = -1
    
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
            isResolvingInteractionPage = true
            syncCurrentPageFromWebView(webView)
        }
    }

    private func syncCurrentPageFromWebView(_ webView: WKWebView) {
        let js = """
        (function() {
            try {
                var perPage = Math.max(1, (typeof getPerPage === 'function' ? getPerPage() : (window.innerWidth || document.documentElement.clientWidth || document.body.clientWidth || 1)));
                var scrollLeft = (typeof getScrollLeft === 'function' ? getScrollLeft() : (window.scrollX || document.documentElement.scrollLeft || document.body.scrollLeft || 0));
                var selection = window.getSelection ? window.getSelection() : null;
                var selectedText = '';
                if (selection && selection.rangeCount > 0) {
                    selectedText = selection.toString ? selection.toString() : '';
                }
                var hasSelection = !!selectedText && selectedText.trim().length > 0;
                return {
                    pageIndex: Math.max(0, Math.round(scrollLeft / perPage)),
                    hasSelection: hasSelection
                };
            } catch (e) {
                return null;
            }
        })();
        """

        webView.evaluateJavaScript(js) { [weak self] value, error in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isResolvingInteractionPage = false

                if let snapshot = Self.parseInteractionSnapshot(from: value), snapshot.hasSelection {
                    let maxPage = max(self.parent.totalPages - 1, 0)
                    let clamped = max(0, min(snapshot.pageIndex, maxPage))
                    self.pendingPageIndex = nil
                    self.lastDisplayedPageIndex = clamped
                    if self.parent.currentPageIndex != clamped {
                        self.parent.currentPageIndex = clamped
                    }
                    return
                }

                if let error {
                    DebugLogger.error("ReaderWebView: 同步交互后页码失败 - \(error.localizedDescription)")
                }
                _ = self.animateToCurrentPageIfChanged(on: webView)
            }
        }
    }

    private static func parseInteractionSnapshot(from value: Any?) -> (pageIndex: Int, hasSelection: Bool)? {
        if let dict = value as? [String: Any] {
            var pageIndex: Int?
            if let index = dict["pageIndex"] as? Int {
                pageIndex = index
            } else if let number = dict["pageIndex"] as? NSNumber {
                pageIndex = number.intValue
            } else if let string = dict["pageIndex"] as? String, let index = Int(string) {
                pageIndex = index
            }

            guard let parsedPage = pageIndex else { return nil }
            let hasSelection: Bool
            if let value = dict["hasSelection"] as? Bool {
                hasSelection = value
            } else if let value = dict["hasSelection"] as? NSNumber {
                hasSelection = value.boolValue
            } else {
                hasSelection = false
            }
            return (parsedPage, hasSelection)
        }
        return nil
    }
    
    private func applyPagination(on webView: WKWebView) {
        guard !didApplyPagination else { return }
        didApplyPagination = true
        let js = "applyPagination()"
        webView.evaluateJavaScript(js) { [weak self] _, _ in
            guard let self = self else { return }
            self.scrollToCurrentPage(on: webView, animated: false)
            self.applyTOCNavigationIfNeeded(on: webView)
        }
    }
    
    /// 通过 JS 通知 Web 进程渲染目标页内容（WKWebView 在 isScrollEnabled=false 时
    /// 不会将原生 contentOffset 变化同步给 Web 渲染进程，必须走 JS）。
    private func jsScrollToPage(_ page: Int, on webView: WKWebView) {
        let js = "scrollToPage(\(page), false)"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func scrollToCurrentPage(on webView: WKWebView, animated: Bool = false) {
        let page = max(0, min(parent.currentPageIndex, max(parent.totalPages - 1, 0)))
        // JS 通知 Web 进程渲染目标区域（必须）
        jsScrollToPage(page, on: webView)
        // 原生 scrollView 同步位置（兜底 + 保证视觉对齐）
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
        if isTouchingContent || isResolvingInteractionPage {
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
        
        // 根据翻页来源选择动画方式
        switch parent.pageTurnStyle {
        case .fade:
            performFadeTransition(to: newIndex, on: webView)
        case .slide:
            performSlideTransition(to: newIndex, on: webView)
        }
        return true
    }
    
    // MARK: - Tap page-turn: snapshot crossfade (120-150ms)
    private func performFadeTransition(to newIndex: Int, on webView: WKWebView) {
        let pageWidth = webView.scrollView.bounds.width
        guard pageWidth > 0 else {
            lastDisplayedPageIndex = newIndex
            scrollToCurrentPage(on: webView, animated: false)
            return
        }

        isAnimatingSlide = true

        // 1. 截取当前页面快照（不等待屏幕更新，保证速度）
        let snapshot = webView.snapshotView(afterScreenUpdates: false)

        if let snapshot = snapshot {
            snapshot.frame = webView.frame
            // 插入到 webView 上方，盖住旧内容
            if let container = containerView {
                container.addSubview(snapshot)
            } else {
                webView.superview?.insertSubview(snapshot, aboveSubview: webView)
            }
        }

        // 2. 通过 JS 告知 Web 进程渲染目标页，同时设置原生 offset
        //    快照覆盖在上层，所以 JS 异步延迟不会被用户看到
        jsScrollToPage(newIndex, on: webView)
        let targetX = CGFloat(newIndex) * pageWidth
        webView.scrollView.setContentOffset(CGPoint(x: targetX, y: 0), animated: false)

        // 3. 淡出快照，露出新页面内容（150ms，克制、不喧宾夺主）
        UIView.animate(
            withDuration: 0.15,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            snapshot?.alpha = 0
        } completion: { [weak self] _ in
            snapshot?.removeFromSuperview()
            guard let self = self else { return }
            self.lastDisplayedPageIndex = newIndex
            self.isAnimatingSlide = false

            // 处理快速连点积压的翻页请求
            if let pending = self.pendingPageIndex, pending != newIndex {
                self.pendingPageIndex = nil
                self.performFadeTransition(to: pending, on: webView)
            } else {
                self.pendingPageIndex = nil
            }
        }
    }
    
    // MARK: - Swipe page-turn: horizontal slide animation
    private func performSlideTransition(to newIndex: Int, on webView: WKWebView) {
        let pageWidth = webView.scrollView.bounds.width
        guard pageWidth > 0 else {
            lastDisplayedPageIndex = newIndex
            scrollToCurrentPage(on: webView, animated: false)
            return
        }

        isAnimatingSlide = true

        let targetOffset = CGFloat(newIndex) * pageWidth

        // JS 通知 Web 进程渲染目标页区域
        jsScrollToPage(newIndex, on: webView)
        // 原生动画滑动（setContentOffset(animated:true) 会持续通知 WKWebView 渲染中间帧）
        webView.scrollView.setContentOffset(CGPoint(x: targetOffset, y: 0), animated: true)

        // 通过短延时检测动画完成（UIScrollView animated scroll 通常 ~0.25s）
        // 使用 DispatchQueue 而非 CATransaction 确保可靠回调
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            guard let self = self else { return }
            self.lastDisplayedPageIndex = newIndex
            self.isAnimatingSlide = false

            if let pending = self.pendingPageIndex, pending != newIndex {
                self.pendingPageIndex = nil
                self.performSlideTransition(to: pending, on: webView)
            } else {
                self.pendingPageIndex = nil
            }
        }
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
        self.isResolvingInteractionPage = false
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

    func applyTOCNavigationIfNeeded(on webView: WKWebView?) {
        guard let webView else { return }
        guard isLoaded else { return }
        guard parent.tocNavigationToken != lastAppliedTOCNavigationToken else { return }

        // Mark this token as consumed even when fragment is empty to avoid repeated checks.
        lastAppliedTOCNavigationToken = parent.tocNavigationToken

        guard let fragment = normalizedFragment(parent.tocNavigationFragment) else { return }
        navigateToTOCFragment(fragment, on: webView)
    }

    private func normalizedFragment(_ fragment: String?) -> String? {
        guard let fragment else { return nil }
        let cleaned = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return cleaned.hasPrefix("#") ? String(cleaned.dropFirst()) : cleaned
    }

    private func navigateToTOCFragment(_ fragment: String, on webView: WKWebView) {
        let escapedFragment = Self.escapeJavaScriptString(fragment)
        let js = """
        (function() {
            try {
                var fragment = "\(escapedFragment)";
                if (!fragment) { return null; }

                function findTarget(key) {
                    if (!key) { return null; }
                    return document.getElementById(key) || document.getElementsByName(key)[0] || null;
                }

                var target = findTarget(fragment);
                if (!target) {
                    try { target = findTarget(decodeURIComponent(fragment)); } catch (e) {}
                }
                if (!target) { return null; }

                var rect = target.getBoundingClientRect();
                var scrollLeft = (typeof getScrollLeft === 'function')
                    ? getScrollLeft()
                    : (window.scrollX || document.documentElement.scrollLeft || document.body.scrollLeft || 0);
                var perPage = Math.max(
                    1,
                    (typeof getPerPage === 'function')
                        ? getPerPage()
                        : (window.innerWidth || document.documentElement.clientWidth || document.body.clientWidth || 1)
                );
                var absoluteX = Math.max(0, rect.left + scrollLeft);
                var page = Math.max(0, Math.floor(absoluteX / perPage));
                if (typeof scrollToPage === 'function') {
                    scrollToPage(page, false);
                } else {
                    window.scrollTo(absoluteX, 0);
                }
                return page;
            } catch (e) {
                return null;
            }
        })();
        """

        webView.evaluateJavaScript(js) { [weak self] value, error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let error {
                    DebugLogger.warning("ReaderWebView: TOC锚点导航失败 - \(error.localizedDescription)")
                    return
                }

                let pageIndex: Int?
                if let page = value as? Int {
                    pageIndex = page
                } else if let number = value as? NSNumber {
                    pageIndex = number.intValue
                } else {
                    pageIndex = nil
                }

                guard let pageIndex else { return }
                let clamped: Int
                if self.parent.totalPages > 0 {
                    let maxPage = max(self.parent.totalPages - 1, 0)
                    clamped = max(0, min(pageIndex, maxPage))
                } else {
                    clamped = max(0, pageIndex)
                }
                self.lastDisplayedPageIndex = clamped
                self.parent.currentPageIndex = clamped
            }
        }
    }

    private static func escapeJavaScriptString(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
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
        let js = """
        (function() {
            applyNativeHighlights(\(jsonString));
            return true;
        })();
        """
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
    var tocNavigationFragment: String?
    var tocNavigationToken: Int = 0
    var pageTurnStyle: PageTurnAnimationStyle = .fade
    
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
            context.coordinator.applyTOCNavigationIfNeeded(on: webView)
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
        let lineHeight: Double
        if appSettings.lineSpacing <= 1.0 {
            // Increase sensitivity below 1.0 so each slider step has clearer visual impact.
            lineHeight = 0.9 + (appSettings.lineSpacing * 0.55)
        } else {
            lineHeight = 1.45 + ((appSettings.lineSpacing - 1.0) * 0.34)
        }
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
            padding: 0 2px !important;
            padding-left: 2px !important;
            padding-right: 2px !important;
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

        function safeNumber(value, fallback) {
            return Number.isFinite(value) ? value : fallback;
        }

        function resolveSelectionRect(range) {
            if (!range) {
                return { x: 0, y: 0, width: 0, height: 0 };
            }

            const viewportWidth = Math.max(1, window.innerWidth || document.documentElement.clientWidth || document.body.clientWidth || 1);
            const viewportHeight = Math.max(1, window.innerHeight || document.documentElement.clientHeight || document.body.clientHeight || 1);
            const viewportTop = 0;
            const viewportLeft = 0;
            const viewportBottom = viewportHeight;
            const viewportRight = viewportWidth;

            let bestRect = null;
            let bestScore = -1;
            const rectList = range.getClientRects ? Array.from(range.getClientRects()) : [];

            rectList.forEach(function(rect) {
                if (!rect) { return; }
                const width = safeNumber(rect.width, 0);
                const height = safeNumber(rect.height, 0);
                const x = safeNumber(rect.x, 0);
                const y = safeNumber(rect.y, 0);
                const visibleWidth = Math.max(0, Math.min(x + width, viewportRight) - Math.max(x, viewportLeft));
                const visibleHeight = Math.max(0, Math.min(y + height, viewportBottom) - Math.max(y, viewportTop));
                const score = visibleWidth * visibleHeight;

                if (score > bestScore) {
                    bestScore = score;
                    bestRect = { x: x, y: y, width: width, height: height };
                }
            });

            if (!bestRect) {
                const fallbackRect = range.getBoundingClientRect();
                bestRect = fallbackRect ? {
                    x: safeNumber(fallbackRect.x, 0),
                    y: safeNumber(fallbackRect.y, 0),
                    width: safeNumber(fallbackRect.width, 0),
                    height: safeNumber(fallbackRect.height, 0)
                } : { x: 0, y: 0, width: 0, height: 0 };
            }

            return bestRect;
        }

        function serializeSelection() {
            const selection = window.getSelection();
            if (!selection || selection.rangeCount === 0) {
                return null;
            }

            const text = selection.toString();
            const range = selection.getRangeAt(0);
            const rect = resolveSelectionRect(range);
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
            const pageIndex = Math.max(0, Math.round(getScrollLeft() / getPerPage()));
            try {
                if (payload) {
                    window.webkit.messageHandlers.textSelection.postMessage(payload);
                } else {
                    window.webkit.messageHandlers.textSelection.postMessage({
                        text: "",
                        start: 0,
                        end: 0,
                        pageIndex: pageIndex,
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

        function findHighlightAncestor(node) {
            let current = node;
            while (current) {
                if (current.nodeType === Node.ELEMENT_NODE && current.classList && current.classList.contains('reader-highlight')) {
                    return current;
                }
                current = current.parentNode;
            }
            return null;
        }

        function normalizeRangeToTextNodeBoundaries(range) {
            if (!range || range.collapsed) { return range; }

            const startContainer = range.startContainer;
            const endContainer = range.endContainer;
            const startOffset = range.startOffset;
            const endOffset = range.endOffset;

            if (startContainer === endContainer && startContainer.nodeType === Node.TEXT_NODE) {
                let textNode = startContainer;
                const length = textNode.length;
                if (length === 0 || startOffset >= endOffset) { return range; }

                if (endOffset > 0 && endOffset < length) {
                    textNode.splitText(endOffset);
                }

                if (startOffset > 0 && startOffset < textNode.length) {
                    textNode = textNode.splitText(startOffset);
                }

                range.setStart(textNode, 0);
                range.setEnd(textNode, textNode.length);
                return range;
            }

            if (endContainer.nodeType === Node.TEXT_NODE) {
                const endLength = endContainer.length;
                if (endOffset > 0 && endOffset < endLength) {
                    endContainer.splitText(endOffset);
                    range.setEnd(endContainer, endContainer.length);
                } else if (endOffset === endLength) {
                    range.setEnd(endContainer, endLength);
                }
            }

            if (startContainer.nodeType === Node.TEXT_NODE) {
                if (startOffset > 0 && startOffset < startContainer.length) {
                    const splitStart = startContainer.splitText(startOffset);
                    range.setStart(splitStart, 0);
                } else if (startOffset === 0) {
                    range.setStart(startContainer, 0);
                }
            }

            return range;
        }

        function collectTextNodesInRange(range) {
            const nodes = [];
            if (!range || range.collapsed) { return nodes; }

            const root = range.commonAncestorContainer;
            if (root.nodeType === Node.TEXT_NODE) {
                if (range.intersectsNode(root) && !findHighlightAncestor(root)) {
                    nodes.push(root);
                }
                return nodes;
            }

            const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
            let node;
            while ((node = walker.nextNode())) {
                const content = node.textContent || '';
                if (!content.length) { continue; }
                if (findHighlightAncestor(node)) { continue; }
                try {
                    if (range.intersectsNode(node)) {
                        nodes.push(node);
                    }
                } catch (e) {}
            }

            return nodes;
        }

        function wrapTextNodeWithHighlight(node, colorHex, highlightId) {
            if (!node || !node.parentNode) { return false; }
            const content = node.textContent || '';
            if (!content.length || content.trim().length === 0) { return false; }

            const wrapper = document.createElement('mark');
            wrapper.className = 'reader-highlight';
            wrapper.style.backgroundColor = normalizeColor(colorHex);
            if (highlightId) {
                wrapper.dataset.highlightId = highlightId;
            }

            node.parentNode.insertBefore(wrapper, node);
            wrapper.appendChild(node);
            return true;
        }

        function wrapRangeWithHighlights(range, colorHex, highlightId) {
            if (!range || range.collapsed) { return false; }
            const workingRange = range.cloneRange();
            normalizeRangeToTextNodeBoundaries(workingRange);
            const textNodes = collectTextNodesInRange(workingRange);
            if (textNodes.length === 0) { return false; }

            var wrappedCount = 0;
            textNodes.forEach(node => {
                if (wrapTextNodeWithHighlight(node, colorHex, highlightId)) {
                    wrappedCount += 1;
                }
            });
            return wrappedCount > 0;
        }

        // 高亮：选区内按文本节点包裹 mark，避免跨段落时只高亮边界
        function applyHighlightForSelection(colorHex) {
            const selection = window.getSelection();
            if (!selection || selection.rangeCount === 0 || !selection.toString()) {
                return false;
            }
            try {
                const payload = serializeSelection();
                if (!payload) { return false; }
                const applied = highlightByOffsets(payload.start, payload.end, colorHex, '');
                if (!applied) { return false; }
                selection.removeAllRanges();
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

        function buildTextSegments() {
            const segments = [];
            const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
            let current = 0;
            let node;

            while ((node = walker.nextNode())) {
                const textLength = (node.textContent || '').length;
                if (textLength <= 0) { continue; }
                const nodeStart = current;
                const nodeEnd = current + textLength;
                segments.push({ node: node, start: nodeStart, end: nodeEnd, length: textLength });
                current = nodeEnd;
            }

            return segments;
        }

        function locateOffsetBoundary(offset, segments, preferNextOnBoundary) {
            if (!segments || segments.length === 0) { return null; }
            const target = Math.max(0, offset);

            for (let i = 0; i < segments.length; i += 1) {
                const segment = segments[i];
                if (target < segment.end) {
                    return { node: segment.node, offset: Math.max(0, target - segment.start) };
                }
                if (target === segment.end) {
                    if (preferNextOnBoundary && i + 1 < segments.length) {
                        return { node: segments[i + 1].node, offset: 0 };
                    }
                    return { node: segment.node, offset: segment.length };
                }
            }

            const last = segments[segments.length - 1];
            return { node: last.node, offset: last.length };
        }

        function highlightByOffsets(start, end, colorHex, highlightId) {
            if (typeof start !== 'number' || typeof end !== 'number' || start >= end) { return false; }
            const segments = buildTextSegments();
            if (segments.length === 0) { return false; }

            const startBoundary = locateOffsetBoundary(start, segments, true);
            const endBoundary = locateOffsetBoundary(end, segments, false);
            if (!startBoundary || !endBoundary) { return false; }
            if (startBoundary.node === endBoundary.node && startBoundary.offset >= endBoundary.offset) {
                return false;
            }

            const range = document.createRange();
            range.setStart(startBoundary.node, startBoundary.offset);
            range.setEnd(endBoundary.node, endBoundary.offset);
            const applied = wrapRangeWithHighlights(range, colorHex, highlightId);
            range.detach();
            return applied;
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
                var groupedHighlights = document.querySelectorAll('mark.reader-highlight[data-highlight-id="' + highlightId + '"]');
                if (groupedHighlights && groupedHighlights.length > 1) {
                    // 多节点高亮时由 Swift 侧回退到持久化全文，避免只拿到局部片段。
                    text = '';
                }
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
