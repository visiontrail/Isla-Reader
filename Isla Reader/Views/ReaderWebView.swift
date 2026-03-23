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
    let canContinueToNextPage: Bool
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
        case continueToNextPage
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
    private var isPaginationReady = false
    private var lastAppliedTOCNavigationToken: Int = -1
    private var lastAppliedHighlightNavigationToken: Int = -1
    private var lastHandledSelectionActionID: UUID?
    private var pendingHTMLLoadToken: Int = 0
    
    init(_ parent: ReaderWebView) {
        self.parent = parent
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DebugLogger.info("[HighlightNav] didFinish: 页面加载完成，准备 applyPagination, highlightToken=\(parent.highlightNavigationToken), highlightOffset=\(parent.highlightTextOffset.map(String.init) ?? "nil")")
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
               let parsed = Self.parseSelectedTextInfo(from: dict) {
                parent.onTextSelection?(parsed)
            } else if let text = message.body as? String {
                parent.onTextSelection?(
                    SelectedTextInfo(
                        text: text,
                        startOffset: 0,
                        endOffset: 0,
                        rect: .zero,
                        pageIndex: 0,
                        canContinueToNextPage: false
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
                    updateTotalPages(value)
                }
            } else if let pages = message.body as? Int {
                updateTotalPages(pages)
            }
        }
    }

    private static func doubleValue(from value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String, let parsed = Double(value) { return parsed }
        return nil
    }

    private static func boolValue(from value: Any?, default defaultValue: Bool = false) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            switch value.lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                break
            }
        }
        return defaultValue
    }

    private static func parseSelectedTextInfo(from dict: [String: Any]) -> SelectedTextInfo? {
        guard let text = dict["text"] as? String else { return nil }

        let start: Int
        if let value = dict["start"] as? Int {
            start = value
        } else if let value = dict["start"] as? NSNumber {
            start = value.intValue
        } else if let value = dict["start"] as? String, let parsed = Int(value) {
            start = parsed
        } else {
            start = 0
        }

        let end: Int
        if let value = dict["end"] as? Int {
            end = value
        } else if let value = dict["end"] as? NSNumber {
            end = value.intValue
        } else if let value = dict["end"] as? String, let parsed = Int(value) {
            end = parsed
        } else {
            end = start
        }

        let pageIndex: Int
        if let value = dict["pageIndex"] as? Int {
            pageIndex = value
        } else if let value = dict["pageIndex"] as? NSNumber {
            pageIndex = value.intValue
        } else if let value = dict["pageIndex"] as? String, let parsed = Int(value) {
            pageIndex = parsed
        } else {
            pageIndex = 0
        }

        let canContinueToNextPage = boolValue(from: dict["canContinueToNextPage"], default: false)
        var rect = CGRect.zero
        if let rectDict = dict["rect"] as? [String: Any] {
            let x = doubleValue(from: rectDict["x"]) ?? 0
            let y = doubleValue(from: rectDict["y"]) ?? 0
            let width = doubleValue(from: rectDict["width"]) ?? 0
            let height = doubleValue(from: rectDict["height"]) ?? 0
            rect = CGRect(x: x, y: y, width: width, height: height)
        } else if let rectDict = dict["rect"] as? [String: Double] {
            let x = rectDict["x"] ?? 0
            let y = rectDict["y"] ?? 0
            let width = rectDict["width"] ?? 0
            let height = rectDict["height"] ?? 0
            rect = CGRect(x: x, y: y, width: width, height: height)
        }

        return SelectedTextInfo(
            text: text,
            startOffset: start,
            endOffset: end,
            rect: rect,
            pageIndex: pageIndex,
            canContinueToNextPage: canContinueToNextPage
        )
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
                var lockedPageIndex = (typeof selectionLockedPageIndex === 'number') ? selectionLockedPageIndex : null;
                return {
                    pageIndex: lockedPageIndex !== null ? lockedPageIndex : Math.max(0, Math.round(scrollLeft / perPage)),
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
                    self.updateCurrentPageIndex(clamped)
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

    private func updateCurrentPageIndex(_ newValue: Int) {
        let clampedValue = max(0, newValue)
        guard parent.currentPageIndex != clampedValue else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.parent.currentPageIndex != clampedValue else { return }
            self.parent.currentPageIndex = clampedValue
        }
    }

    private func updateTotalPages(_ newValue: Int) {
        let clampedValue = max(0, newValue)
        guard parent.totalPages != clampedValue else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.parent.totalPages != clampedValue else { return }
            self.parent.totalPages = clampedValue
        }
    }
    
    private func applyPagination(on webView: WKWebView) {
        guard !didApplyPagination else { return }
        didApplyPagination = true
        isPaginationReady = false
        let js = "applyPagination()"
        webView.evaluateJavaScript(js) { [weak self] _, _ in
            guard let self = self else { return }
            self.isPaginationReady = true
            DebugLogger.info("[HighlightNav] applyPagination 完成，准备调用 applyHighlightNavigationIfNeeded")
            self.scrollToCurrentPage(on: webView, animated: false)
            self.applyTOCNavigationIfNeeded(on: webView)
            self.applyHighlightNavigationIfNeeded(on: webView)
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
        pendingHTMLLoadToken += 1
        self.didApplyPagination = false
        self.isLoaded = false
        self.isPaginationReady = false
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

    func loadHTMLAsync(cacheKey: String, htmlContent: String, css: String, on webView: WKWebView) {
        pendingHTMLLoadToken += 1
        let requestToken = pendingHTMLLoadToken

        ReaderWebView.renderHTMLAsync(cacheKey: cacheKey, htmlContent: htmlContent, css: css) { [weak self, weak webView] html in
            DispatchQueue.main.async {
                guard let self, let webView else { return }
                guard requestToken == self.pendingHTMLLoadToken else { return }
                webView.loadHTMLString(html, baseURL: nil)
            }
        }
    }

    func applyTOCNavigationIfNeeded(on webView: WKWebView?) {
        guard let webView else { return }
        guard isLoaded else { return }
        guard isPaginationReady else { return }
        guard parent.tocNavigationToken != lastAppliedTOCNavigationToken else { return }

        // Mark this token as consumed even when fragment is empty to avoid repeated checks.
        lastAppliedTOCNavigationToken = parent.tocNavigationToken

        guard let fragment = normalizedFragment(parent.tocNavigationFragment) else { return }
        navigateToTOCFragment(fragment, on: webView)
    }

    func applyHighlightNavigationIfNeeded(on webView: WKWebView?) {
        DebugLogger.info("[HighlightNav] applyHighlightNavigationIfNeeded 进入: webView=\(webView != nil), isLoaded=\(isLoaded), paginationReady=\(isPaginationReady), parentToken=\(parent.highlightNavigationToken), lastAppliedToken=\(lastAppliedHighlightNavigationToken), parentOffset=\(parent.highlightTextOffset.map(String.init) ?? "nil")")
        guard let webView else {
            DebugLogger.warning("[HighlightNav] applyHighlightNavigationIfNeeded: webView 为 nil，跳过")
            return
        }
        guard isLoaded else {
            DebugLogger.info("[HighlightNav] applyHighlightNavigationIfNeeded: isLoaded=false，跳过（等待加载完成）")
            return
        }
        guard isPaginationReady else {
            DebugLogger.info("[HighlightNav] applyHighlightNavigationIfNeeded: paginationReady=false，跳过（等待分页完成）")
            return
        }
        guard parent.highlightNavigationToken != lastAppliedHighlightNavigationToken else {
            DebugLogger.info("[HighlightNav] applyHighlightNavigationIfNeeded: token 已消费 (\(parent.highlightNavigationToken))，跳过")
            return
        }
        lastAppliedHighlightNavigationToken = parent.highlightNavigationToken
        guard let offset = parent.highlightTextOffset else {
            DebugLogger.warning("[HighlightNav] applyHighlightNavigationIfNeeded: highlightTextOffset 为 nil，跳过")
            return
        }
        DebugLogger.info("[HighlightNav] 开始执行 navigateToTextOffset, offset=\(offset)")
        navigateToTextOffset(offset, on: webView)
    }

    private func navigateToTextOffset(_ offset: Int, on webView: WKWebView) {
        let js = "getPageForTextOffset(\(offset))"
        DebugLogger.info("[HighlightNav] 执行 JS: \(js)")
        webView.evaluateJavaScript(js) { [weak self] value, error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let error {
                    DebugLogger.error("[HighlightNav] JS 执行失败: \(error.localizedDescription)")
                    return
                }

                DebugLogger.info("[HighlightNav] JS 返回值: \(String(describing: value)), 类型: \(type(of: value))")

                let pageIndex: Int?
                if let page = value as? Int {
                    pageIndex = page
                } else if let number = value as? NSNumber {
                    pageIndex = number.intValue
                } else {
                    DebugLogger.warning("[HighlightNav] JS 返回值无法解析为页码")
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
                DebugLogger.info("[HighlightNav] 导航结果: JS页码=\(pageIndex), clamped=\(clamped), totalPages=\(self.parent.totalPages), 之前页码=\(self.parent.currentPageIndex)")
                self.lastDisplayedPageIndex = clamped
                self.updateCurrentPageIndex(clamped)
                self.scrollToCurrentPage(on: webView, animated: false)
                DebugLogger.info("[HighlightNav] 页码已更新为 \(clamped)，scrollToCurrentPage 已调用")
            }
        }
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
                self.updateCurrentPageIndex(clamped)
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
        case .continueToNextPage:
            _ = webView.becomeFirstResponder()
            let js = """
            (function() {
                try {
                    return continueSelectionToNextPage();
                } catch (e) {
                    return { success: false, error: String(e) };
                }
            })();
            """
            webView.evaluateJavaScript(js) { [weak self] value, error in
                guard let self else { return }
                if let error {
                    DebugLogger.error("ReaderWebView: 继续跨页选择失败 - \(error.localizedDescription)")
                    return
                }
                guard let response = value as? [String: Any] else {
                    DebugLogger.warning("ReaderWebView: 继续跨页选择返回值无效")
                    return
                }
                let success = Self.boolValue(from: response["success"], default: false)
                guard success else {
                    if let reason = response["reason"] as? String, !reason.isEmpty {
                        DebugLogger.warning("ReaderWebView: 继续跨页选择未执行，reason=\(reason)")
                    }
                    return
                }
                guard let selectionDict = response["selection"] as? [String: Any],
                      let parsedSelection = Self.parseSelectedTextInfo(from: selectionDict) else {
                    DebugLogger.warning("ReaderWebView: 继续跨页选择成功但未返回有效选区")
                    return
                }

                DispatchQueue.main.async {
                    let clamped: Int
                    if self.parent.totalPages > 0 {
                        let maxPage = max(self.parent.totalPages - 1, 0)
                        clamped = max(0, min(parsedSelection.pageIndex, maxPage))
                    } else {
                        clamped = max(0, parsedSelection.pageIndex)
                    }
                    self.lastDisplayedPageIndex = clamped
                    self.updateCurrentPageIndex(clamped)
                    self.parent.onTextSelection?(parsedSelection)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        webView.resignFirstResponder()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            _ = webView.becomeFirstResponder()
                        }
                    }
                }
            }
        }
    }

    func performSelectionActionIfNeeded(_ action: ReaderSelectionAction?, on webView: WKWebView) {
        guard let action else { return }
        guard lastHandledSelectionActionID != action.id else { return }
        lastHandledSelectionActionID = action.id
        performSelectionAction(action, on: webView)
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
    private static let renderedHTMLCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 12
        return cache
    }()
    private static let htmlRenderQueue = DispatchQueue(
        label: "lanread.reader.html-render",
        qos: .userInitiated,
        attributes: .concurrent
    )

    let contentID: Int
    let htmlContent: String
    let appSettings: AppSettings
    let isDarkMode: Bool
    @Binding var currentPageIndex: Int
    @Binding var totalPages: Int
    @Binding var selectionAction: ReaderSelectionAction?
    var highlights: [ReaderHighlight]
    var tocNavigationFragment: String?
    var tocNavigationToken: Int = 0
    var highlightTextOffset: Int?
    var highlightNavigationToken: Int = 0
    var pageTurnStyle: PageTurnAnimationStyle = .fade
    
    var onToolbarToggle: (() -> Void)?
    var onTextSelection: ((SelectedTextInfo) -> Void)?
    var onHighlightTap: ((HighlightTapInfo) -> Void)?
    var onLoadFinished: (() -> Void)?
    var onInteractionChange: ((Bool) -> Void)?

    static func preloadChapterHTML(
        contentID: Int,
        htmlContent: String,
        fontSize: CGFloat,
        lineSpacing: Double,
        isDarkMode: Bool,
        pageMargins: Int
    ) {
        let styleSignature = makeStyleSignature(
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            isDarkMode: isDarkMode,
            pageMargins: pageMargins
        )
        let cacheKey = makeCacheKey(contentID: contentID, styleSignature: styleSignature)
        if renderedHTMLCache.object(forKey: cacheKey as NSString) != nil {
            return
        }

        let css = getMobileOptimizedCSS(
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            isDarkMode: isDarkMode,
            pageMargins: pageMargins
        )
        renderHTMLAsync(cacheKey: cacheKey, htmlContent: htmlContent, css: css, completion: { _ in })
    }

    fileprivate static func renderHTMLAsync(
        cacheKey: String,
        htmlContent: String,
        css: String,
        completion: @escaping (String) -> Void
    ) {
        if let cached = renderedHTMLCache.object(forKey: cacheKey as NSString) {
            completion(cached as String)
            return
        }

        htmlRenderQueue.async {
            let html = buildFullHTML(htmlContent: htmlContent, css: css)
            renderedHTMLCache.setObject(html as NSString, forKey: cacheKey as NSString)
            completion(html)
        }
    }

    private static func buildFullHTML(htmlContent: String, css: String) -> String {
        """
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
                <div class="reader-book-root">
                    \(htmlContent)
                </div>
            </div>
        </body>
        </html>
        """
    }

    private static func makeStyleSignature(
        fontSize: CGFloat,
        lineSpacing: Double,
        isDarkMode: Bool,
        pageMargins: Int
    ) -> String {
        let roundedFont = Int(fontSize.rounded())
        let roundedLineSpacing = String(format: "%.3f", lineSpacing)
        return "font:\(roundedFont)|line:\(roundedLineSpacing)|theme:\(isDarkMode ? "dark" : "light")|margin:\(pageMargins)"
    }

    private static func makeCacheKey(contentID: Int, styleSignature: String) -> String {
        "chapter:\(contentID)|\(styleSignature)"
    }
    
    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(self)
    }
    
    func makeUIView(context: Context) -> UIView {
        let configuration = WKWebViewConfiguration()
        configuration.selectionGranularity = .character
        
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
        let styleSignature = Self.makeStyleSignature(
            fontSize: appSettings.readingFontSize.fontSize,
            lineSpacing: appSettings.lineSpacing,
            isDarkMode: isDarkMode,
            pageMargins: Int(appSettings.pageMargins)
        )
        let cacheKey = Self.makeCacheKey(contentID: contentID, styleSignature: styleSignature)
        let signature = "sig::\(cacheKey)"
        if container.accessibilityHint != signature {
            DebugLogger.info("[HighlightNav] updateUIView: 签名变化，重新加载 HTML, highlightToken=\(highlightNavigationToken), highlightOffset=\(highlightTextOffset.map(String.init) ?? "nil")")
            container.accessibilityHint = signature
            context.coordinator.prepareForNewLoad()
            let css = getMobileOptimizedCSS()
            if let cachedHTML = Self.renderedHTMLCache.object(forKey: cacheKey as NSString) {
                webView.loadHTMLString(cachedHTML as String, baseURL: nil)
            } else {
                context.coordinator.loadHTMLAsync(
                    cacheKey: cacheKey,
                    htmlContent: htmlContent,
                    css: css,
                    on: webView
                )
            }
        } else {
            DebugLogger.info("[HighlightNav] updateUIView: 签名未变，走 else 分支, highlightToken=\(highlightNavigationToken), highlightOffset=\(highlightTextOffset.map(String.init) ?? "nil")")
            // 内容未重载：仅在页码真正变化时同步，避免文本选择过程中被旧页码强制拉回。
            _ = context.coordinator.animateToCurrentPageIfChanged(on: webView)
            context.coordinator.applyTOCNavigationIfNeeded(on: webView)
            context.coordinator.applyHighlightNavigationIfNeeded(on: webView)
        }

        context.coordinator.performSelectionActionIfNeeded(selectionAction, on: webView)
    }

    private func getMobileOptimizedCSS() -> String {
        Self.getMobileOptimizedCSS(
            fontSize: appSettings.readingFontSize.fontSize,
            lineSpacing: appSettings.lineSpacing,
            isDarkMode: isDarkMode,
            pageMargins: Int(appSettings.pageMargins)
        )
    }

    private static func getMobileOptimizedCSS(
        fontSize: CGFloat,
        lineSpacing: Double,
        isDarkMode: Bool,
        pageMargins: Int
    ) -> String {
        let lineHeight: Double
        if lineSpacing <= 1.0 {
            // Increase sensitivity below 1.0 so each slider step has clearer visual impact.
            lineHeight = 0.9 + (lineSpacing * 0.55)
        } else {
            lineHeight = 1.45 + ((lineSpacing - 1.0) * 0.34)
        }
        let backgroundColor = isDarkMode ? "#0d0d12" : "#fafafa"
        let textColor = isDarkMode ? "rgba(255, 255, 255, 0.87)" : "rgba(0, 0, 0, 0.87)"
        let linkColor = isDarkMode ? "#64b5f6" : "#1976d2"
        let pageMargin = Int(pageMargins)

        return """
        /* 基础样式 - 移动端优化 */
        :root {
            --reader-page-margin: \(pageMargin)px;
        }

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

        /* 单一版心容器：仅在这里应用用户页边距，避免嵌套元素叠加造成正文过窄 */
        .reader-book-root {
            width: 100%;
            max-width: 100%;
            min-height: 100%;
            margin: 0;
            padding-left: var(--reader-page-margin);
            padding-right: var(--reader-page-margin);
        }
        
        /* 清理由EPUB内容带入的横向布局限制，统一由用户页边距控制 */
        .reader-book-root div,
        .reader-book-root article,
        .reader-book-root section,
        .reader-book-root aside,
        .reader-book-root nav,
        .reader-book-root header,
        .reader-book-root footer,
        .reader-book-root main,
        .reader-book-root figure,
        .reader-book-root table {
            width: auto;
            max-width: 100%;
            margin-left: 0;
            margin-right: 0;
            padding-left: 0;
            padding-right: 0;
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
            padding-left: 1em !important;
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
        var selectionLockedPageIndex = null;
        var isRestoringSelectionPage = false;
        var selectionScrollLockEnabled = false;
        var selectionScrollUnlockDepth = 0;
        var isContinuingSelectionToNextPage = false;
        var lastStableSelectionPayload = null;
        var continuedSelectionAnchorOffset = null;
        var continuedSelectionNativeStartOffset = null;
        var continuedSelectionNativeEndOffset = null;
        var isRepairingContinuedNativeSelection = false;
        var selectionVisualOverlay = null;
        var selectionVisualHighlight = null;
        var selectionVisualStartHandle = null;
        var selectionVisualEndHandle = null;

        function setHorizontalOverflowMode(mode) {
            const resolvedMode = mode === 'hidden' ? 'hidden' : 'auto';
            document.documentElement.style.overflowX = resolvedMode;
            document.body.style.overflowX = resolvedMode;
            document.documentElement.style.overflowY = 'hidden';
            document.body.style.overflowY = 'hidden';
        }

        function ensureSelectionVisualOverlay() {
            if (selectionVisualOverlay) { return selectionVisualOverlay; }

            const overlay = document.createElement('div');
            overlay.setAttribute('aria-hidden', 'true');
            overlay.style.position = 'fixed';
            overlay.style.left = '0';
            overlay.style.top = '0';
            overlay.style.width = '100vw';
            overlay.style.height = '100vh';
            overlay.style.pointerEvents = 'none';
            overlay.style.zIndex = '2147483646';
            overlay.style.display = 'none';

            const highlight = document.createElement('div');
            highlight.style.position = 'fixed';
            highlight.style.borderRadius = '8px';
            highlight.style.background = 'rgba(64, 156, 255, 0.24)';
            highlight.style.boxShadow = '0 0 0 1px rgba(64, 156, 255, 0.28) inset';

            const startHandle = document.createElement('div');
            startHandle.style.position = 'fixed';
            startHandle.style.width = '14px';
            startHandle.style.height = '14px';
            startHandle.style.borderRadius = '999px';
            startHandle.style.background = '#ffffff';
            startHandle.style.border = '2px solid rgba(64, 156, 255, 0.96)';
            startHandle.style.boxShadow = '0 2px 8px rgba(0, 0, 0, 0.18)';

            const endHandle = startHandle.cloneNode(false);

            overlay.appendChild(highlight);
            overlay.appendChild(startHandle);
            overlay.appendChild(endHandle);

            if (document.body) {
                document.body.appendChild(overlay);
            } else {
                document.documentElement.appendChild(overlay);
            }

            selectionVisualOverlay = overlay;
            selectionVisualHighlight = highlight;
            selectionVisualStartHandle = startHandle;
            selectionVisualEndHandle = endHandle;
            return overlay;
        }

        function hideSelectionVisualOverlay() {
            if (!selectionVisualOverlay) { return; }
            selectionVisualOverlay.style.display = 'none';
        }

        function updateSelectionVisualOverlay(payload) {
            if (continuedSelectionAnchorOffset === null || !selectionHasText(payload)) {
                hideSelectionVisualOverlay();
                return;
            }

            const rect = payload && payload.rect ? payload.rect : null;
            if (!rect) {
                hideSelectionVisualOverlay();
                return;
            }

            const viewportWidth = Math.max(1, window.innerWidth || document.documentElement.clientWidth || document.body.clientWidth || 1);
            const viewportHeight = Math.max(1, window.innerHeight || document.documentElement.clientHeight || document.body.clientHeight || 1);
            const rawLeft = safeNumber(rect.x, 0);
            const rawTop = safeNumber(rect.y, 0);
            const rawWidth = safeNumber(rect.width, 0);
            const rawHeight = safeNumber(rect.height, 0);
            const clampedLeft = Math.max(0, Math.min(rawLeft, viewportWidth - 1));
            const clampedTop = Math.max(0, Math.min(rawTop, viewportHeight - 1));
            const visibleWidth = Math.max(0, Math.min(rawLeft + rawWidth, viewportWidth) - clampedLeft);
            const visibleHeight = Math.max(0, Math.min(rawTop + rawHeight, viewportHeight) - clampedTop);
            if (visibleWidth <= 1 || visibleHeight <= 1) {
                hideSelectionVisualOverlay();
                return;
            }

            ensureSelectionVisualOverlay();

            const handleSize = 14;
            const handleRadius = handleSize / 2;
            const handleY = Math.max(0, Math.min(viewportHeight - handleSize, clampedTop + visibleHeight - handleRadius));
            const startHandleX = Math.max(0, Math.min(viewportWidth - handleSize, clampedLeft - handleRadius));
            const endHandleX = Math.max(0, Math.min(viewportWidth - handleSize, clampedLeft + visibleWidth - handleRadius));

            selectionVisualHighlight.style.left = clampedLeft + 'px';
            selectionVisualHighlight.style.top = clampedTop + 'px';
            selectionVisualHighlight.style.width = visibleWidth + 'px';
            selectionVisualHighlight.style.height = visibleHeight + 'px';

            selectionVisualStartHandle.style.left = startHandleX + 'px';
            selectionVisualStartHandle.style.top = handleY + 'px';

            selectionVisualEndHandle.style.left = endHandleX + 'px';
            selectionVisualEndHandle.style.top = handleY + 'px';

            selectionVisualOverlay.style.display = 'block';
        }

        function withSelectionScrollUnlocked(work) {
            selectionScrollUnlockDepth += 1;
            if (selectionScrollLockEnabled) {
                setHorizontalOverflowMode('auto');
            }
            try {
                return work();
            } finally {
                selectionScrollUnlockDepth = Math.max(0, selectionScrollUnlockDepth - 1);
                if (selectionScrollUnlockDepth === 0) {
                    setHorizontalOverflowMode(selectionScrollLockEnabled ? 'hidden' : 'auto');
                }
            }
        }

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

        function selectionHasText(payload) {
            if (!payload || typeof payload.text !== 'string') { return false; }
            return payload.text.trim().length > 0;
        }

        function cloneSelectionPayload(payload) {
            if (!payload) { return null; }
            return {
                text: payload.text || '',
                start: typeof payload.start === 'number' ? payload.start : 0,
                end: typeof payload.end === 'number' ? payload.end : 0,
                pageIndex: typeof payload.pageIndex === 'number' ? payload.pageIndex : 0,
                rect: {
                    x: payload.rect && typeof payload.rect.x === 'number' ? payload.rect.x : 0,
                    y: payload.rect && typeof payload.rect.y === 'number' ? payload.rect.y : 0,
                    width: payload.rect && typeof payload.rect.width === 'number' ? payload.rect.width : 0,
                    height: payload.rect && typeof payload.rect.height === 'number' ? payload.rect.height : 0
                },
                canContinueToNextPage: !!payload.canContinueToNextPage
            };
        }

        function extractTextFromOffsets(startOffset, endOffset, segments) {
            const range = buildRangeFromOffsets(startOffset, endOffset, segments);
            if (!range) { return ''; }
            const text = range.toString ? range.toString() : '';
            range.detach();
            return text || '';
        }

        function focusReaderDocument() {
            try { window.focus(); } catch (e) {}
            try {
                if (document.body && document.body.setAttribute) {
                    document.body.setAttribute('tabindex', '-1');
                }
                if (document.body && document.body.focus) {
                    document.body.focus({ preventScroll: true });
                }
            } catch (e) {
                try {
                    if (document.body && document.body.focus) {
                        document.body.focus();
                    }
                } catch (ignore) {}
            }
        }

        function applyNativeSelectionRange(startOffset, endOffset, segments) {
            const resolvedSegments = segments || buildTextSegments();
            const startBoundary = locateOffsetBoundary(startOffset, resolvedSegments, true);
            const endBoundary = locateOffsetBoundary(endOffset, resolvedSegments, false);
            if (!startBoundary || !endBoundary) { return false; }
            if (startBoundary.node === endBoundary.node && startBoundary.offset >= endBoundary.offset) {
                return false;
            }

            const selection = window.getSelection();
            if (!selection) { return false; }

            focusReaderDocument();
            selection.removeAllRanges();

            let applied = false;
            if (typeof selection.setBaseAndExtent === 'function') {
                try {
                    selection.setBaseAndExtent(
                        startBoundary.node,
                        startBoundary.offset,
                        endBoundary.node,
                        endBoundary.offset
                    );
                    applied = selection.rangeCount > 0 && !!selection.toString();
                } catch (e) {}
            }

            if (!applied && typeof selection.collapse === 'function' && typeof selection.extend === 'function') {
                try {
                    selection.collapse(startBoundary.node, startBoundary.offset);
                    selection.extend(endBoundary.node, endBoundary.offset);
                    applied = selection.rangeCount > 0 && !!selection.toString();
                } catch (e) {}
            }

            if (!applied) {
                const range = document.createRange();
                range.setStart(startBoundary.node, startBoundary.offset);
                range.setEnd(endBoundary.node, endBoundary.offset);
                try {
                    selection.removeAllRanges();
                    selection.addRange(range);
                    applied = selection.rangeCount > 0 && !!selection.toString();
                } catch (e) {
                    applied = false;
                }
                range.detach();
            }

            return applied;
        }

        function buildEffectiveSelectionPayload(nativePayload, segments) {
            if (!nativePayload) { return null; }
            const payload = cloneSelectionPayload(nativePayload);
            if (continuedSelectionAnchorOffset === null) { return payload; }

            const resolvedSegments = segments || buildTextSegments();
            if (!resolvedSegments || resolvedSegments.length === 0) { return payload; }

            const combinedStart = Math.min(continuedSelectionAnchorOffset, nativePayload.start);
            const combinedEnd = Math.max(continuedSelectionAnchorOffset, nativePayload.end);
            if (combinedStart >= combinedEnd) { return payload; }

            const combinedText = extractTextFromOffsets(combinedStart, combinedEnd, resolvedSegments);
            payload.text = combinedText || payload.text;
            payload.start = combinedStart;
            payload.end = combinedEnd;
            return payload;
        }

        function getTotalPageCount() {
            const totalWidth = getTotalWidth();
            const perPage = getPerPage();
            return Math.max(1, Math.ceil(totalWidth / perPage));
        }

        function setSelectionScrollLock(enabled) {
            selectionScrollLockEnabled = !!enabled;
            if (selectionScrollUnlockDepth === 0) {
                setHorizontalOverflowMode(selectionScrollLockEnabled ? 'hidden' : 'auto');
            }
        }

        function enforceSelectionLockedPageIfNeeded() {
            if (selectionLockedPageIndex === null || isRestoringSelectionPage || isContinuingSelectionToNextPage) { return; }
            const currentPage = Math.max(0, Math.round(getScrollLeft() / getPerPage()));
            if (currentPage === selectionLockedPageIndex) { return; }
            isRestoringSelectionPage = true;
            scrollToPage(selectionLockedPageIndex, false);
            isRestoringSelectionPage = false;
        }

        function findNextNonWhitespaceOffset(fromOffset, segments) {
            if (!segments || segments.length === 0) { return null; }
            const target = Math.max(0, fromOffset);
            const whitespacePattern = /\\s/;
            for (let i = 0; i < segments.length; i += 1) {
                const segment = segments[i];
                if (segment.end <= target) { continue; }
                const text = segment.node && segment.node.textContent ? segment.node.textContent : '';
                const localStart = Math.max(0, target - segment.start);
                for (let j = localStart; j < text.length; j += 1) {
                    const char = text.charAt(j);
                    if (!whitespacePattern.test(char)) {
                        return segment.start + j;
                    }
                }
            }
            return null;
        }

        function estimatePageIndexForOffset(offset, segments) {
            const boundary = locateOffsetBoundary(offset, segments, true);
            if (!boundary || !boundary.node) { return null; }

            const nodeText = boundary.node.textContent || '';
            const safeOffset = Math.max(0, Math.min(boundary.offset, nodeText.length));
            const probeRange = document.createRange();
            probeRange.setStart(boundary.node, safeOffset);
            probeRange.setEnd(boundary.node, safeOffset);

            let rect = null;
            const rects = probeRange.getClientRects ? probeRange.getClientRects() : null;
            if (rects && rects.length > 0) {
                rect = rects[0];
            } else if (probeRange.getBoundingClientRect) {
                rect = probeRange.getBoundingClientRect();
            }
            probeRange.detach();

            if (!rect) { return null; }
            const perPage = getPerPage();
            const absoluteX = safeNumber(rect.left, 0) + getScrollLeft();
            return Math.max(0, Math.floor(Math.max(0, absoluteX) / perPage));
        }

        function shouldOfferContinueSelectionToNextPage(payload) {
            if (!payload) { return false; }
            const totalPages = getTotalPageCount();
            if (payload.pageIndex >= totalPages - 1) { return false; }

            const segments = buildTextSegments();
            if (!segments || segments.length === 0) { return false; }

            const nextOffset = findNextNonWhitespaceOffset(payload.end, segments);
            if (nextOffset === null) { return false; }

            const nextOffsetPage = estimatePageIndexForOffset(nextOffset, segments);
            if (nextOffsetPage === null) { return false; }
            return nextOffsetPage > payload.pageIndex;
        }

        function notifySelectionChange() {
            if (isContinuingSelectionToNextPage) { return; }
            const pageIndex = Math.max(0, Math.round(getScrollLeft() / getPerPage()));
            const segments = buildTextSegments();
            let nativePayload = serializeSelection();
            let payload = null;
            if (selectionHasText(nativePayload)) {
                setSelectionScrollLock(true);
                if (selectionLockedPageIndex === null) {
                    selectionLockedPageIndex = nativePayload.pageIndex;
                }

                if (nativePayload.pageIndex !== selectionLockedPageIndex &&
                    !isRestoringSelectionPage) {
                    isRestoringSelectionPage = true;
                    scrollToPage(selectionLockedPageIndex, false);
                    isRestoringSelectionPage = false;
                    const restoredPayload = serializeSelection();
                    if (selectionHasText(restoredPayload)) {
                        nativePayload = restoredPayload;
                    }
                    nativePayload.pageIndex = selectionLockedPageIndex;
                } else {
                    selectionLockedPageIndex = nativePayload.pageIndex;
                }

                payload = buildEffectiveSelectionPayload(nativePayload, segments);
                payload.canContinueToNextPage = shouldOfferContinueSelectionToNextPage(payload);
                continuedSelectionNativeStartOffset = nativePayload.start;
                continuedSelectionNativeEndOffset = nativePayload.end;
                lastStableSelectionPayload = cloneSelectionPayload(payload);
                updateSelectionVisualOverlay(payload);
            } else {
                const currentPage = Math.max(0, Math.round(getScrollLeft() / getPerPage()));
                const shouldKeepStableSelection =
                    selectionLockedPageIndex !== null &&
                    lastStableSelectionPayload &&
                    (
                        lastInteractionState ||
                        currentPage !== selectionLockedPageIndex ||
                        isRestoringSelectionPage
                    );

                // 场景2（段落跨页）在某些 WebKit 时序下会短暂丢失原生选区，先尝试按最近一次
                // native offsets 恢复，避免退化成仅 overlay（无系统拖拽手柄）。
                if (
                    shouldKeepStableSelection &&
                    continuedSelectionAnchorOffset !== null &&
                    !isRepairingContinuedNativeSelection &&
                    typeof continuedSelectionNativeStartOffset === 'number' &&
                    typeof continuedSelectionNativeEndOffset === 'number' &&
                    continuedSelectionNativeEndOffset > continuedSelectionNativeStartOffset
                ) {
                    isRepairingContinuedNativeSelection = true;
                    try {
                        var repairSegments = buildTextSegments();
                        if (!repairSegments || repairSegments.length === 0) {
                            repairSegments = segments;
                        }
                        var repaired = applyNativeSelectionRange(
                            continuedSelectionNativeStartOffset,
                            continuedSelectionNativeEndOffset,
                            repairSegments
                        );
                        if (repaired) {
                            var repairedNative = serializeSelection();
                            if (selectionHasText(repairedNative)) {
                                setSelectionScrollLock(true);
                                if (selectionLockedPageIndex === null) {
                                    selectionLockedPageIndex = repairedNative.pageIndex;
                                }
                                payload = buildEffectiveSelectionPayload(repairedNative, repairSegments);
                                payload.pageIndex = selectionLockedPageIndex;
                                payload.canContinueToNextPage = shouldOfferContinueSelectionToNextPage(payload);
                                continuedSelectionNativeStartOffset = repairedNative.start;
                                continuedSelectionNativeEndOffset = repairedNative.end;
                                lastStableSelectionPayload = cloneSelectionPayload(payload);
                                updateSelectionVisualOverlay(payload);
                            }
                        }
                    } catch (e) {} finally {
                        isRepairingContinuedNativeSelection = false;
                    }
                }

                if (!payload && shouldKeepStableSelection) {
                    payload = cloneSelectionPayload(lastStableSelectionPayload);
                    payload.pageIndex = selectionLockedPageIndex;
                    payload.canContinueToNextPage = shouldOfferContinueSelectionToNextPage(payload);
                    updateSelectionVisualOverlay(payload);
                } else if (!shouldKeepStableSelection) {
                    selectionLockedPageIndex = null;
                    lastStableSelectionPayload = null;
                    continuedSelectionAnchorOffset = null;
                    continuedSelectionNativeStartOffset = null;
                    continuedSelectionNativeEndOffset = null;
                    setSelectionScrollLock(false);
                    hideSelectionVisualOverlay();
                    payload = null;
                }
            }
            try {
                if (payload) {
                    window.webkit.messageHandlers.textSelection.postMessage(payload);
                } else {
                    window.webkit.messageHandlers.textSelection.postMessage({
                        text: "",
                        start: 0,
                        end: 0,
                        pageIndex: pageIndex,
                        rect: { x: 0, y: 0, width: 0, height: 0 },
                        canContinueToNextPage: false
                    });
                }
            } catch (e) {}
        }

        // 文本选择处理
        document.addEventListener('selectionchange', notifySelectionChange);
        document.addEventListener('touchstart', function(){ notifyInteraction(true); }, { passive: true });
        document.addEventListener('touchend', function(){ notifyInteraction(false); }, { passive: true });
        document.addEventListener('touchcancel', function(){ notifyInteraction(false); }, { passive: true });
        document.addEventListener('touchmove', function() {
            if (selectionLockedPageIndex === null || isContinuingSelectionToNextPage) { return; }
            enforceSelectionLockedPageIfNeeded();
        }, { passive: true });
        
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
            // 默认允许程序化横向滚动，但在文本选择锁页时收紧到当前页。
            setHorizontalOverflowMode(selectionScrollLockEnabled && selectionScrollUnlockDepth === 0 ? 'hidden' : 'auto');
            // 重新计算页数
            setTimeout(function(){ computePageCount(); updateEdgeOverlay(); }, 0);
        }
        
        function setScrollLeft(x, animated) {
            withSelectionScrollUnlocked(function() {
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
            });
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
        
        var selectionRectSyncScheduled = false;
        function syncSelectionRectAfterScrollIfNeeded() {
            enforceSelectionLockedPageIfNeeded();
            if (selectionRectSyncScheduled) { return; }
            selectionRectSyncScheduled = true;
            requestAnimationFrame(function() {
                selectionRectSyncScheduled = false;
                enforceSelectionLockedPageIfNeeded();
                updateEdgeOverlay();
                try {
                    const selection = window.getSelection ? window.getSelection() : null;
                    if (!selection || selection.rangeCount === 0) { return; }
                    const text = selection.toString ? selection.toString().trim() : '';
                    if (!text) { return; }
                    const payload = buildEffectiveSelectionPayload(serializeSelection(), buildTextSegments());
                    updateSelectionVisualOverlay(payload);
                    notifySelectionChange();
                } catch (e) {}
            });
        }
        window.addEventListener('scroll', syncSelectionRectAfterScrollIfNeeded, { passive: true });
        
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
                const segments = buildTextSegments();
                const payload = buildEffectiveSelectionPayload(serializeSelection(), segments);
                if (!payload) { return false; }
                const applied = highlightByOffsets(payload.start, payload.end, colorHex, '');
                if (!applied) { return false; }
                selection.removeAllRanges();
                selectionLockedPageIndex = null;
                lastStableSelectionPayload = null;
                continuedSelectionAnchorOffset = null;
                continuedSelectionNativeStartOffset = null;
                continuedSelectionNativeEndOffset = null;
                setSelectionScrollLock(false);
                hideSelectionVisualOverlay();
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

        function findWordEndOffset(startOffset, segments) {
            if (!segments || segments.length === 0) { return null; }
            const target = Math.max(0, startOffset);
            const whitespacePattern = /\\s/;
            let hasConsumedWordChar = false;

            for (let i = 0; i < segments.length; i += 1) {
                const segment = segments[i];
                if (segment.end <= target) { continue; }
                const text = segment.node && segment.node.textContent ? segment.node.textContent : '';
                let localIndex = Math.max(0, target - segment.start);
                while (localIndex < text.length) {
                    const char = text.charAt(localIndex);
                    const isWhitespace = whitespacePattern.test(char);
                    if (!hasConsumedWordChar) {
                        if (!isWhitespace) {
                            hasConsumedWordChar = true;
                        }
                    } else if (isWhitespace) {
                        return segment.start + localIndex;
                    }
                    localIndex += 1;
                }
                if (hasConsumedWordChar) {
                    return segment.end;
                }
            }

            return null;
        }

        function isCJKCharacter(char) {
            return /[\\u3040-\\u30ff\\u3400-\\u4dbf\\u4e00-\\u9fff\\uf900-\\ufaff\\uac00-\\ud7af]/.test(char);
        }

        function findLineEndOffset(startOffset, segments) {
            if (!segments || segments.length === 0) { return null; }
            var startBoundary = locateOffsetBoundary(startOffset, segments, true);
            if (!startBoundary || !startBoundary.node) { return null; }

            var nodeLen = (startBoundary.node.textContent || '').length;
            var probeEnd = Math.min(startBoundary.offset + 1, nodeLen);
            if (probeEnd <= startBoundary.offset) { return null; }

            var probeRange = document.createRange();
            probeRange.setStart(startBoundary.node, startBoundary.offset);
            probeRange.setEnd(startBoundary.node, probeEnd);
            var rects = probeRange.getClientRects();
            probeRange.detach();

            if (!rects || rects.length === 0) { return null; }
            var startTop = rects[0].top;
            var lineThreshold = Math.max(rects[0].height * 0.5, 2);

            var lastSameLineOffset = startOffset + 1;
            var charsScanned = 0;
            var maxChars = 200;

            for (var i = 0; i < segments.length && charsScanned < maxChars; i++) {
                var seg = segments[i];
                if (seg.end <= startOffset + 1) { continue; }

                var text = seg.node.textContent || '';
                var localStart = Math.max(0, (startOffset + 1) - seg.start);

                for (var j = localStart; j < text.length && charsScanned < maxChars; j++) {
                    charsScanned++;
                    var charEnd = Math.min(j + 1, text.length);
                    if (charEnd <= j) { continue; }
                    var charRange = document.createRange();
                    charRange.setStart(seg.node, j);
                    charRange.setEnd(seg.node, charEnd);
                    var charRects = charRange.getClientRects();
                    charRange.detach();

                    if (!charRects || charRects.length === 0) { continue; }
                    if (Math.abs(charRects[0].top - startTop) > lineThreshold) {
                        return lastSameLineOffset;
                    }
                    lastSameLineOffset = seg.start + j + 1;
                }
            }

            return lastSameLineOffset;
        }

        function resolveParagraphContainer(node) {
            var current = node ? node.parentElement : null;
            while (current && current !== document.body && current !== document.documentElement) {
                var tag = current.tagName ? current.tagName.toUpperCase() : '';
                if (
                    tag === 'P' ||
                    tag === 'DIV' ||
                    tag === 'LI' ||
                    tag === 'BLOCKQUOTE' ||
                    tag === 'SECTION' ||
                    tag === 'ARTICLE' ||
                    tag === 'DD' ||
                    tag === 'DT' ||
                    tag === 'H1' ||
                    tag === 'H2' ||
                    tag === 'H3' ||
                    tag === 'H4' ||
                    tag === 'H5' ||
                    tag === 'H6'
                ) {
                    return current;
                }
                current = current.parentElement;
            }
            return null;
        }

        function findParagraphEndOffset(startOffset, segments, maxCharacters) {
            if (!segments || segments.length === 0) { return null; }
            var boundary = locateOffsetBoundary(startOffset, segments, true);
            if (!boundary || !boundary.node) { return null; }

            var container = resolveParagraphContainer(boundary.node);
            if (!container) { return null; }

            var whitespacePattern = /\\s/;
            var maxChars = Math.max(32, Math.floor(maxCharacters || 220));
            var consumed = 0;
            var lastNonWhitespace = null;
            var started = false;

            for (var i = 0; i < segments.length; i++) {
                var seg = segments[i];
                if (seg.end <= startOffset) { continue; }
                if (!container.contains(seg.node)) {
                    if (started) { break; }
                    continue;
                }
                started = true;

                var text = seg.node && seg.node.textContent ? seg.node.textContent : '';
                var localStart = Math.max(0, startOffset - seg.start);
                for (var j = localStart; j < text.length; j++) {
                    var char = text.charAt(j);
                    if (!char) { continue; }
                    if (!whitespacePattern.test(char)) {
                        consumed += 1;
                        lastNonWhitespace = seg.start + j + 1;
                        if (consumed >= maxChars) {
                            return lastNonWhitespace;
                        }
                    }
                }
            }

            return lastNonWhitespace;
        }

        function findSeedSelectionEndOffset(startOffset, segments) {
            if (!segments || segments.length === 0) { return null; }

            var lineEnd = findLineEndOffset(startOffset, segments);
            if (lineEnd !== null && lineEnd > startOffset) {
                return lineEnd;
            }

            var boundary = locateOffsetBoundary(startOffset, segments, true);
            if (!boundary || !boundary.node) { return null; }
            var text = boundary.node.textContent || '';
            var safeOffset = Math.max(0, Math.min(boundary.offset, Math.max(text.length - 1, 0)));
            var leadingChar = text.charAt(safeOffset);
            if (!leadingChar) { return null; }
            if (isCJKCharacter(leadingChar)) {
                return startOffset + 1;
            }
            var wordEnd = findWordEndOffset(startOffset, segments);
            if (wordEnd !== null && wordEnd > startOffset) {
                return wordEnd;
            }
            return startOffset + 1;
        }

        function findOffsetAfterCharacterCount(startOffset, minCharacters, segments) {
            if (!segments || segments.length === 0) { return null; }
            const target = Math.max(0, startOffset);
            const requiredChars = Math.max(1, Math.floor(minCharacters || 1));
            const whitespacePattern = /\\s/;
            let consumed = 0;
            let lastOffset = null;

            for (let i = 0; i < segments.length; i += 1) {
                const segment = segments[i];
                if (segment.end <= target) { continue; }
                const text = segment.node && segment.node.textContent ? segment.node.textContent : '';
                let localIndex = Math.max(0, target - segment.start);

                while (localIndex < text.length) {
                    const char = text.charAt(localIndex);
                    if (!char) {
                        localIndex += 1;
                        continue;
                    }
                    if (whitespacePattern.test(char)) {
                        if (consumed > 0) {
                            return segment.start + localIndex;
                        }
                        localIndex += 1;
                        continue;
                    }
                    consumed += 1;
                    lastOffset = segment.start + localIndex + 1;
                    if (consumed >= requiredChars) {
                        return lastOffset;
                    }
                    localIndex += 1;
                }
            }

            return lastOffset;
        }

        function resolveSeedSelectionEndOffset(startOffset, segments) {
            if (!segments || segments.length === 0) { return startOffset + 1; }

            const seedEnd = findSeedSelectionEndOffset(startOffset, segments);
            if (seedEnd !== null && seedEnd > startOffset + 1) {
                return seedEnd;
            }

            const paragraphEnd = findParagraphEndOffset(startOffset, segments, 260);
            if (paragraphEnd !== null && paragraphEnd > startOffset + 1) {
                return paragraphEnd;
            }

            const boundary = locateOffsetBoundary(startOffset, segments, true);
            const text = boundary && boundary.node ? (boundary.node.textContent || '') : '';
            const safeOffset = Math.max(
                0,
                Math.min(boundary ? boundary.offset : 0, Math.max(text.length - 1, 0))
            );
            const leadingChar = text.charAt(safeOffset);

            if (leadingChar && isCJKCharacter(leadingChar)) {
                const expanded = findOffsetAfterCharacterCount(startOffset, 12, segments);
                if (expanded !== null && expanded > startOffset + 1) {
                    return expanded;
                }
            }

            if (seedEnd !== null && seedEnd > startOffset) {
                return seedEnd;
            }
            return startOffset + 1;
        }

        function applySeedSelectionRange(startOffset, endOffset, segments) {
            if (!segments || segments.length === 0) { return false; }
            if (!(endOffset > startOffset)) { return false; }

            // 优先使用原生 Range 选区，确保 iOS 可拖拽手柄可用。
            if (applyNativeSelectionRange(startOffset, endOffset, segments)) {
                return true;
            }

            // 退化路径：window.find 先找到文本后，再次尝试落回原生 Range。
            var seedText = extractTextFromOffsets(startOffset, endOffset, segments);
            if (!(seedText && seedText.trim().length > 0) || typeof window.find !== 'function') {
                return false;
            }

            var startBoundary = locateOffsetBoundary(startOffset, segments, true);
            if (!startBoundary || !startBoundary.node) {
                return false;
            }

            focusReaderDocument();
            var selection = window.getSelection();
            if (selection) {
                try {
                    selection.removeAllRanges();
                    selection.collapse(startBoundary.node, startBoundary.offset);
                } catch (e) {}
            }

            var found = false;
            try {
                found = !!withSelectionScrollUnlocked(function() {
                    var savedScroll = getScrollLeft();
                    var matched = !!window.find(seedText, true, false, false, false, false, false);
                    if (getScrollLeft() !== savedScroll) {
                        window.scrollTo(savedScroll, 0);
                    }
                    return matched;
                });
            } catch (e) {}

            if (!found) {
                return false;
            }
            return applyNativeSelectionRange(startOffset, endOffset, segments) || found;
        }

        function buildRangeFromOffsets(startOffset, endOffset, segments) {
            if (typeof startOffset !== 'number' || typeof endOffset !== 'number') { return null; }
            if (startOffset >= endOffset) { return null; }
            const startBoundary = locateOffsetBoundary(startOffset, segments, true);
            const endBoundary = locateOffsetBoundary(endOffset, segments, false);
            if (!startBoundary || !endBoundary) { return null; }
            if (startBoundary.node === endBoundary.node && startBoundary.offset >= endBoundary.offset) {
                return null;
            }
            const range = document.createRange();
            range.setStart(startBoundary.node, startBoundary.offset);
            range.setEnd(endBoundary.node, endBoundary.offset);
            return range;
        }

        function continueSelectionToNextPage() {
            if (isContinuingSelectionToNextPage) {
                return { success: false, reason: 'busy' };
            }
            isContinuingSelectionToNextPage = true;
            var rafScheduled = false;
            try {
                const nativePayload = serializeSelection();
                if (!selectionHasText(nativePayload)) {
                    return { success: false, reason: 'empty-selection' };
                }

                const segments = buildTextSegments();
                if (!segments || segments.length === 0) {
                    return { success: false, reason: 'no-segments' };
                }

                const payload = buildEffectiveSelectionPayload(nativePayload, segments);
                if (!selectionHasText(payload)) {
                    return { success: false, reason: 'effective-selection-empty' };
                }

                const currentPage = (selectionLockedPageIndex !== null) ? selectionLockedPageIndex : payload.pageIndex;
                const totalPages = getTotalPageCount();
                if (currentPage >= totalPages - 1) {
                    return { success: false, reason: 'already-last-page' };
                }
                if (!shouldOfferContinueSelectionToNextPage(payload)) {
                    return { success: false, reason: 'no-continue-opportunity' };
                }

                const nextStartOffset = findNextNonWhitespaceOffset(payload.end, segments);
                if (nextStartOffset === null) {
                    return { success: false, reason: 'no-next-text' };
                }
                const nextPageOffset = estimatePageIndexForOffset(nextStartOffset, segments);
                if (nextPageOffset === null || nextPageOffset <= currentPage) {
                    return { success: false, reason: 'next-page-unresolved' };
                }
                const nextPage = Math.min(totalPages - 1, nextPageOffset);

                continuedSelectionAnchorOffset = payload.start;
                selectionLockedPageIndex = nextPage;
                isRestoringSelectionPage = true;
                scrollToPage(nextPage, false);
                isRestoringSelectionPage = false;

                var selectionSegments = buildTextSegments();
                if (!selectionSegments || selectionSegments.length === 0) {
                    selectionSegments = segments;
                }
                var targetEndOffset = resolveSeedSelectionEndOffset(nextStartOffset, selectionSegments);
                if (!(targetEndOffset > nextStartOffset)) {
                    targetEndOffset = nextStartOffset + 1;
                }

                var selectionApplied = applySeedSelectionRange(nextStartOffset, targetEndOffset, selectionSegments);
                if (!selectionApplied) {
                    return { success: false, reason: 'seed-selection-apply-failed' };
                }

                const updatedNative = serializeSelection();
                if (!selectionHasText(updatedNative)) {
                    return { success: false, reason: 'updated-selection-empty' };
                }
                const updated = buildEffectiveSelectionPayload(updatedNative, selectionSegments);
                updated.pageIndex = nextPage;
                updated.canContinueToNextPage = shouldOfferContinueSelectionToNextPage(updated);
                continuedSelectionNativeStartOffset = updatedNative.start;
                continuedSelectionNativeEndOffset = updatedNative.end;
                lastStableSelectionPayload = cloneSelectionPayload(updated);
                updateSelectionVisualOverlay(updated);

                rafScheduled = true;
                requestAnimationFrame(function() {
                    try {
                        focusReaderDocument();
                        var currentNative = serializeSelection();
                        if (selectionHasText(currentNative)) {
                            var refreshedSegments = buildTextSegments();
                            var refreshed = buildEffectiveSelectionPayload(currentNative, refreshedSegments);
                            refreshed.pageIndex = nextPage;
                            refreshed.canContinueToNextPage = shouldOfferContinueSelectionToNextPage(refreshed);
                            continuedSelectionNativeStartOffset = currentNative.start;
                            continuedSelectionNativeEndOffset = currentNative.end;
                            lastStableSelectionPayload = cloneSelectionPayload(refreshed);
                            updateSelectionVisualOverlay(refreshed);
                            try { window.webkit.messageHandlers.textSelection.postMessage(refreshed); } catch (e) {}
                        } else {
                            var freshSegments = buildTextSegments();
                            if (!freshSegments || freshSegments.length === 0) {
                                freshSegments = selectionSegments;
                            }
                            var freshTargetEndOffset = resolveSeedSelectionEndOffset(nextStartOffset, freshSegments);
                            if (!(freshTargetEndOffset > nextStartOffset)) {
                                freshTargetEndOffset = targetEndOffset;
                            }
                            var reapplied2 = applySeedSelectionRange(nextStartOffset, freshTargetEndOffset, freshSegments);
                            if (reapplied2) {
                                focusReaderDocument();
                                var reappliedNative = serializeSelection();
                                if (selectionHasText(reappliedNative)) {
                                    var reapplied = buildEffectiveSelectionPayload(reappliedNative, freshSegments);
                                    reapplied.pageIndex = nextPage;
                                    reapplied.canContinueToNextPage = shouldOfferContinueSelectionToNextPage(reapplied);
                                    continuedSelectionNativeStartOffset = reappliedNative.start;
                                    continuedSelectionNativeEndOffset = reappliedNative.end;
                                    lastStableSelectionPayload = cloneSelectionPayload(reapplied);
                                    updateSelectionVisualOverlay(reapplied);
                                    try { window.webkit.messageHandlers.textSelection.postMessage(reapplied); } catch (e) {}
                                }
                            }
                        }
                    } catch (e) {}
                    setTimeout(function() {
                        isContinuingSelectionToNextPage = false;
                        notifySelectionChange();
                    }, 50);
                });

                try { window.webkit.messageHandlers.textSelection.postMessage(updated); } catch (e) {}
                return { success: true, selection: updated };
            } finally {
                if (!rafScheduled) {
                    isContinuingSelectionToNextPage = false;
                }
            }
        }

        function getPageForTextOffset(offset) {
            console.log('[HighlightNav JS] getPageForTextOffset called, offset=' + offset);
            var segments = buildTextSegments();
            console.log('[HighlightNav JS] segments count=' + segments.length + ', total chars=' + (segments.length > 0 ? segments[segments.length - 1].end : 0));
            var boundary = locateOffsetBoundary(offset, segments, true);
            if (!boundary) {
                console.log('[HighlightNav JS] locateOffsetBoundary returned null, returning page 0');
                return 0;
            }
            console.log('[HighlightNav JS] boundary found: nodeOffset=' + boundary.offset + ', nodeText=' + (boundary.node.textContent || '').substring(0, 30));

            // In WebKit multi-column layout, geometry APIs can report column-local x.
            // Use scrollIntoView to let the engine resolve the containing column, then
            // convert the resulting scroll position back into page index.
            var marker = document.createElement('span');
            marker.style.cssText = 'display:inline;width:0;height:0;padding:0;margin:0;border:none;overflow:visible;font-size:0;line-height:0;vertical-align:baseline;';
            var nodeLen = (boundary.node.textContent || '').length;
            var insertOffset = Math.min(boundary.offset, nodeLen);
            var originalScrollLeft = getScrollLeft();
            var targetScrollLeft = originalScrollLeft;
            try {
                var insertRange = document.createRange();
                insertRange.setStart(boundary.node, insertOffset);
                insertRange.collapse(true);
                insertRange.insertNode(marker);
                insertRange.detach();
                try {
                    marker.scrollIntoView({ behavior: 'instant', block: 'nearest', inline: 'start' });
                } catch (e1) {
                    try { marker.scrollIntoView(true); } catch (e2) {}
                }
                targetScrollLeft = getScrollLeft();
            } catch (e) {
                console.log('[HighlightNav JS] marker insertion/scroll failed: ' + e);
            } finally {
                if (marker.parentNode) {
                    var p = marker.parentNode;
                    p.removeChild(marker);
                    try { p.normalize(); } catch (e2) {}
                }
                setScrollLeft(originalScrollLeft, false);
            }
            var perPage = getPerPage();
            var page = Math.max(0, Math.round(Math.max(0, targetScrollLeft) / perPage));
            console.log('[HighlightNav JS] originalScroll=' + originalScrollLeft + ', targetScroll=' + targetScrollLeft + ', perPage=' + perPage + ', resultPage=' + page);
            return page;
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
            var selectionToRestore = null;
            try {
                var sel = window.getSelection ? window.getSelection() : null;
                if (sel && sel.rangeCount > 0) {
                    var selText = sel.toString ? sel.toString() : '';
                    if (selText && selText.trim().length > 0) {
                        var savedPayload = serializeSelection();
                        if (selectionHasText(savedPayload)) {
                            selectionToRestore = { start: savedPayload.start, end: savedPayload.end };
                        }
                    }
                }
            } catch (e) {}
            clearExistingHighlights();
            if (items && Array.isArray(items)) {
                items.forEach(item => {
                    highlightByOffsets(item.start, item.end, item.colorHex || '#ffe38f', item.id || '');
                });
            }
            if (selectionToRestore) {
                try {
                    var segments = buildTextSegments();
                    applyNativeSelectionRange(selectionToRestore.start, selectionToRestore.end, segments);
                } catch (e) {}
            }
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
