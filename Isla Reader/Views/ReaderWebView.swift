//
//  ReaderWebView.swift
//  LanRead
//
//  Created by AI Assistant on 2025/10/27.
//

import SwiftUI
import WebKit
import QuartzCore

struct SelectedTextInfo: Equatable {
    let text: String
    let startOffset: Int
    let endOffset: Int
    let rect: CGRect
    let pageIndex: Int
    let canContinueToNextPage: Bool
    let isSplitParagraphTailRegion: Bool
}

struct HighlightTapInfo: Equatable {
    let id: UUID
    let text: String
}

struct ReaderLinkTapInfo: Equatable {
    let href: String
    let text: String
    let isExternal: Bool
    let isFootnoteHint: Bool
    let isTOCHint: Bool
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
    private var needsHighlightSync = true
    private var isApplyingHighlights = false
    private var lastSelectionFocusRepairTimestamp: CFTimeInterval = 0
    private var lastAppliedSelectionMaintenanceSuspended: Bool?
    private var lastSelectionVisualNudgeKey: String?
    private var lastSelectionVisualNudgeTimestamp: CFTimeInterval = 0
    private var splitTailNudgeDirection: CGFloat = 1
    
    init(_ parent: ReaderWebView) {
        self.parent = parent
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DebugLogger.info("[HighlightNav] didFinish: 页面加载完成，准备 applyPagination, highlightToken=\(parent.highlightNavigationToken), highlightOffset=\(parent.highlightTextOffset.map(String.init) ?? "nil")")
        applyPagination(on: webView)
        isLoaded = true
        lastAppliedSelectionMaintenanceSuspended = nil
        lastDisplayedPageIndex = parent.currentPageIndex
        scrollToCurrentPage(on: webView, animated: false)
        parent.onLoadFinished?()
        applyHighlightsIfReady(on: webView)
        applySelectionMaintenanceModeIfNeeded(on: webView)
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
                ensureWebViewFirstResponderForSelectionIfNeeded(trigger: "textSelection.dict", selectedText: parsed.text)
                triggerNativeSelectionVisualNudgeIfNeeded(selection: parsed, trigger: "textSelection.dict")
                parent.onTextSelection?(parsed)
            } else if let text = message.body as? String {
                ensureWebViewFirstResponderForSelectionIfNeeded(trigger: "textSelection.string", selectedText: text)
                parent.onTextSelection?(
                    SelectedTextInfo(
                        text: text,
                        startOffset: 0,
                        endOffset: 0,
                        rect: .zero,
                        pageIndex: 0,
                        canContinueToNextPage: false,
                        isSplitParagraphTailRegion: false
                    )
                )
            }
        } else if message.name == "selectionDebug" {
            if let dict = message.body as? [String: Any] {
                let label = (dict["label"] as? String) ?? "unknown"
                let details = (dict["details"] as? String) ?? ""
                DebugLogger.info("[SelectionDebug] \(label) \(details)")
            } else if let text = message.body as? String {
                DebugLogger.info("[SelectionDebug] \(text)")
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
        } else if message.name == "contentLinkTap" {
            if let dict = message.body as? [String: Any],
               let rawHref = dict["href"] as? String {
                let href = rawHref.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !href.isEmpty else { return }
                let text = ((dict["text"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                parent.onContentLinkTap?(
                    ReaderLinkTapInfo(
                        href: href,
                        text: text,
                        isExternal: Self.boolValue(from: dict["isExternal"], default: false),
                        isFootnoteHint: Self.boolValue(from: dict["isFootnoteHint"], default: false),
                        isTOCHint: Self.boolValue(from: dict["isTOCHint"], default: false)
                    )
                )
            }
        } else if message.name == "pageMetrics" {
            if let dict = message.body as? [String: Any] {
                if let type = dict["type"] as? String, let value = dict["value"] as? Int {
                    if type == "pageCount" {
                        updateTotalPages(value)
                    } else if type == "currentPage" {
                        let clamped: Int
                        if parent.totalPages > 0 {
                            let maxPage = max(parent.totalPages - 1, 0)
                            clamped = max(0, min(value, maxPage))
                        } else {
                            clamped = max(0, value)
                        }
                        lastDisplayedPageIndex = clamped
                        updateCurrentPageIndex(clamped)
                    }
                }
            } else if let pages = message.body as? Int {
                updateTotalPages(pages)
            }
        }
    }

    private func ensureWebViewFirstResponderForSelectionIfNeeded(trigger: String, selectedText: String) {
        let trimmedText = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        guard !parent.isSelectionInputFocused else {
            DebugLogger.info("[SelectionDebug] selection.focus.repair.skip trigger=\(trigger),reason=selectionInputFocused")
            return
        }
        guard let webView else { return }
        guard !webView.isFirstResponder else { return }

        let now = CACurrentMediaTime()
        // Avoid hammering becomeFirstResponder on every selectionchange callback.
        guard now - lastSelectionFocusRepairTimestamp > 0.2 else { return }
        lastSelectionFocusRepairTimestamp = now

        DebugLogger.info("[SelectionDebug] selection.focus.repair.begin trigger=\(trigger),isFirstResponder=\(webView.isFirstResponder)")
        DispatchQueue.main.async { [weak webView] in
            guard let webView else { return }
            if webView.isFirstResponder {
                DebugLogger.info("[SelectionDebug] selection.focus.repair.skip trigger=\(trigger),reason=alreadyFirstResponder")
                return
            }
            let requested = webView.becomeFirstResponder()
            DebugLogger.info("[SelectionDebug] selection.focus.repair.end trigger=\(trigger),requested=\(requested),isFirstResponder=\(webView.isFirstResponder)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak webView] in
                guard let webView else { return }
                DebugLogger.info("[SelectionDebug] selection.focus.repair.later trigger=\(trigger),isFirstResponder=\(webView.isFirstResponder)")
            }
        }
    }

    private func triggerNativeSelectionVisualNudgeIfNeeded(selection: SelectedTextInfo, trigger: String) {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        guard selection.isSplitParagraphTailRegion else { return }
        let trimmedText = selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        let safeStart = min(selection.startOffset, selection.endOffset)
        let safeEnd = max(selection.startOffset, selection.endOffset)
        let selectionLength = safeEnd - safeStart
        guard selectionLength > 0 else { return }
        guard selectionLength <= 220 else { return }

        let key = "\(selection.pageIndex):\(safeStart)"
        let now = CACurrentMediaTime()
        if lastSelectionVisualNudgeKey == key,
           now - lastSelectionVisualNudgeTimestamp < 0.065 {
            return
        }
        lastSelectionVisualNudgeKey = key
        lastSelectionVisualNudgeTimestamp = now

        DebugLogger.info("[SelectionDebug] selection.trickNudge.trigger trigger=\(trigger),key=\(key),len=\(selectionLength),splitTail=true")
        DebugLogger.info("[SelectionDebug] selection.uiNudge.begin trigger=\(trigger),key=\(key),len=\(selectionLength),splitTail=true")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let webView = self.webView else {
                DebugLogger.info("[SelectionDebug] selection.uiNudge.end trigger=\(trigger),key=\(key),applied=false,reason=noWebView")
                return
            }

            let scrollView = webView.scrollView
            let originalOffset = scrollView.contentOffset
            let contentWidth = max(scrollView.contentSize.width, scrollView.bounds.width)
            let maxX = max(0, contentWidth - scrollView.bounds.width)
            var nudgedX = originalOffset.x + self.splitTailNudgeDirection
            if nudgedX > maxX || nudgedX < 0 {
                self.splitTailNudgeDirection *= -1
                nudgedX = originalOffset.x + self.splitTailNudgeDirection
                if nudgedX > maxX || nudgedX < 0 {
                    nudgedX = originalOffset.x
                }
            }

            if nudgedX == originalOffset.x {
                if let containerView = self.containerView {
                    let originalTransform = containerView.transform
                    UIView.performWithoutAnimation {
                        containerView.transform = originalTransform.translatedBy(x: 1.0, y: 0)
                        containerView.layoutIfNeeded()
                        containerView.transform = originalTransform
                        containerView.layoutIfNeeded()
                    }
                    DebugLogger.info("[SelectionDebug] selection.uiNudge.end trigger=\(trigger),key=\(key),applied=true,mode=containerTransform")
                } else {
                    DebugLogger.info("[SelectionDebug] selection.uiNudge.end trigger=\(trigger),key=\(key),applied=false,reason=noContainer")
                }
                return
            }
            self.splitTailNudgeDirection *= -1

            UIView.performWithoutAnimation {
                scrollView.setContentOffset(CGPoint(x: nudgedX, y: originalOffset.y), animated: false)
                scrollView.layoutIfNeeded()
                scrollView.setContentOffset(originalOffset, animated: false)
                scrollView.layoutIfNeeded()
            }
            DebugLogger.info(
                "[SelectionDebug] selection.uiNudge.end trigger=\(trigger),key=\(key),applied=true,mode=nativeOffset,from=\(originalOffset.x),to=\(nudgedX)"
            )
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
        let rawText = (dict["text"] as? String) ?? ""
        let cleanedText = (dict["cleanedText"] as? String) ?? rawText
        let text = SelectionTextSanitizer.sanitizedForHighlightAndAI(cleanedText)

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
        let isSplitParagraphTailRegion = boolValue(from: dict["isSplitParagraphTailRegion"], default: false)
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
            canContinueToNextPage: canContinueToNextPage,
            isSplitParagraphTailRegion: isSplitParagraphTailRegion
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
        
        // If an animation is in-flight:
        // - tap/fade: keep latest queued target for rapid taps
        // - swipe/slide: never queue extra targets, enforce one page per swipe
        if isAnimatingSlide {
            if parent.pageTurnStyle == .fade {
                pendingPageIndex = newIndex
            }
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
    
    // MARK: - Tap page-turn: near-instant crossfade (Apple Books style)
    private func performFadeTransition(to newIndex: Int, on webView: WKWebView) {
        let pageWidth = webView.scrollView.bounds.width
        guard pageWidth > 0 else {
            lastDisplayedPageIndex = newIndex
            scrollToCurrentPage(on: webView, animated: false)
            return
        }

        isAnimatingSlide = true

        let snapshot = webView.snapshotView(afterScreenUpdates: false)

        if let snapshot = snapshot {
            snapshot.frame = webView.bounds
            if let container = containerView {
                container.addSubview(snapshot)
            } else {
                webView.superview?.insertSubview(snapshot, aboveSubview: webView)
            }
        }

        jsScrollToPage(newIndex, on: webView)
        let targetX = CGFloat(newIndex) * pageWidth
        webView.scrollView.setContentOffset(CGPoint(x: targetX, y: 0), animated: false)

        UIView.animate(
            withDuration: 0.12,
            delay: 0,
            options: [.curveEaseIn, .beginFromCurrentState, .allowUserInteraction]
        ) {
            snapshot?.alpha = 0
        } completion: { [weak self] _ in
            snapshot?.removeFromSuperview()
            guard let self = self else { return }
            self.lastDisplayedPageIndex = newIndex
            self.isAnimatingSlide = false

            if let pending = self.pendingPageIndex, pending != newIndex {
                self.pendingPageIndex = nil
                self.performFadeTransition(to: pending, on: webView)
            } else {
                self.pendingPageIndex = nil
            }
        }
    }

    // MARK: - Swipe page-turn: Apple Books-style slide with shadow
    private func performSlideTransition(to newIndex: Int, on webView: WKWebView) {
        let pageWidth = webView.scrollView.bounds.width
        guard pageWidth > 0 else {
            lastDisplayedPageIndex = newIndex
            scrollToCurrentPage(on: webView, animated: false)
            return
        }

        isAnimatingSlide = true
        let isForward = newIndex > lastDisplayedPageIndex

        let snapshot = webView.snapshotView(afterScreenUpdates: false)
        let shadowView = UIView()

        if let snapshot = snapshot {
            snapshot.frame = webView.bounds
            if let container = containerView {
                container.addSubview(snapshot)
            } else {
                webView.superview?.insertSubview(snapshot, aboveSubview: webView)
            }

            shadowView.frame = CGRect(
                x: isForward ? -20 : snapshot.bounds.width,
                y: 0,
                width: 20,
                height: snapshot.bounds.height
            )
            shadowView.backgroundColor = .clear
            let gradient = CAGradientLayer()
            gradient.frame = shadowView.bounds
            gradient.startPoint = CGPoint(x: isForward ? 0 : 1, y: 0.5)
            gradient.endPoint = CGPoint(x: isForward ? 1 : 0, y: 0.5)
            gradient.colors = [
                UIColor.black.withAlphaComponent(0).cgColor,
                UIColor.black.withAlphaComponent(0.08).cgColor
            ]
            shadowView.layer.addSublayer(gradient)
            snapshot.addSubview(shadowView)
            snapshot.clipsToBounds = false
        }

        jsScrollToPage(newIndex, on: webView)
        let targetX = CGFloat(newIndex) * pageWidth
        webView.scrollView.setContentOffset(CGPoint(x: targetX, y: 0), animated: false)

        let slideDistance = pageWidth * 0.35
        let finalX = isForward ? -slideDistance : slideDistance

        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            usingSpringWithDamping: 1.0,
            initialSpringVelocity: 0.5,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            snapshot?.transform = CGAffineTransform(translationX: finalX, y: 0)
            snapshot?.alpha = 0.3
            shadowView.alpha = 0
        } completion: { [weak self] _ in
            snapshot?.removeFromSuperview()
            guard let self = self else { return }
            self.lastDisplayedPageIndex = newIndex
            self.isAnimatingSlide = false

            // Slide mode strictly handles one page per swipe.
            self.pendingPageIndex = nil
        }
    }

    // Sync latest SwiftUI state to coordinator
    func updateParent(_ newParent: ReaderWebView) {
        self.parent = newParent
    }

    func applySelectionMaintenanceModeIfNeeded(on webView: WKWebView?) {
        guard let webView else { return }
        guard isLoaded else { return }

        let shouldSuspend = parent.isSelectionInputFocused
        guard lastAppliedSelectionMaintenanceSuspended != shouldSuspend else { return }

        let jsFlag = shouldSuspend ? "true" : "false"
        let js = """
        (function() {
            if (typeof setSelectionMaintenanceSuspended !== 'function') {
                return false;
            }
            return setSelectionMaintenanceSuspended(\(jsFlag), 'swift.updateUIView');
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.lastAppliedSelectionMaintenanceSuspended = nil
                DebugLogger.warning("ReaderWebView: 更新选区维护挂起状态失败 - \(error.localizedDescription)")
                return
            }
            self.lastAppliedSelectionMaintenanceSuspended = shouldSuspend
            DebugLogger.info("[SelectionDebug] selection.maintenance.swift suspend=\(shouldSuspend)")
        }
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
        needsHighlightSync = true
        isApplyingHighlights = false
        lastAppliedSelectionMaintenanceSuspended = nil
    }

    func updateHighlights(_ highlights: [ReaderHighlight]) {
        if pendingHighlights != highlights {
            pendingHighlights = highlights
            needsHighlightSync = true
        }
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
                DebugLogger.info("ReaderWebView: 继续跨页选择响应 - \(response)")
                let success = Self.boolValue(from: response["success"], default: false)
                guard success else {
                    if let reason = response["reason"] as? String, !reason.isEmpty {
                        DebugLogger.warning("ReaderWebView: 继续跨页选择未执行，reason=\(reason)")
                    }
                    return
                }
                DispatchQueue.main.async {
                    let parsedSelection = (response["selection"] as? [String: Any]).flatMap(Self.parseSelectedTextInfo)
                    let rawPageIndex: Int
                    if let parsedSelection {
                        rawPageIndex = parsedSelection.pageIndex
                    } else if let value = response["pageIndex"] as? Int {
                        rawPageIndex = value
                    } else if let value = response["pageIndex"] as? NSNumber {
                        rawPageIndex = value.intValue
                    } else if let value = response["pageIndex"] as? String, let parsed = Int(value) {
                        rawPageIndex = parsed
                    } else {
                        rawPageIndex = self.parent.currentPageIndex
                    }

                    let clamped: Int
                    if self.parent.totalPages > 0 {
                        let maxPage = max(self.parent.totalPages - 1, 0)
                        clamped = max(0, min(rawPageIndex, maxPage))
                    } else {
                        clamped = max(0, rawPageIndex)
                    }
                    self.lastDisplayedPageIndex = clamped
                    self.updateCurrentPageIndex(clamped)
                    if let parsedSelection {
                        self.parent.onTextSelection?(parsedSelection)
                    }
                    // Avoid resignFirstResponder/becomeFirstResponder cycle: iOS auto-restores
                    // the native text selection (with drag handles) only at paragraph-boundary
                    // positions. For mid-paragraph continuations (Scene 2), the resign clears
                    // the native selection and becomeFirstResponder does not restore it, leaving
                    // the user with no drag handles. Instead, just ensure the WebView stays
                    // first responder so the native selection and handles remain intact.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if !webView.isFirstResponder {
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
        guard needsHighlightSync else { return }
        guard !isApplyingHighlights else { return }
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
        isApplyingHighlights = true
        let snapshot = pendingHighlights
        let js = """
        (function() {
            applyNativeHighlights(\(jsonString));
            return true;
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] _, error in
            guard let self else { return }
            self.isApplyingHighlights = false
            if let error {
                DebugLogger.error("ReaderWebView: 同步高亮失败 - \(error.localizedDescription)")
                return
            }

            if self.pendingHighlights == snapshot {
                self.needsHighlightSync = false
            } else {
                self.needsHighlightSync = true
                self.applyHighlightsIfReady(on: webView)
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

    let contentID: String
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
    var isSelectionInputFocused: Bool = false
    
    var onToolbarToggle: (() -> Void)?
    var onTextSelection: ((SelectedTextInfo) -> Void)?
    var onHighlightTap: ((HighlightTapInfo) -> Void)?
    var onContentLinkTap: ((ReaderLinkTapInfo) -> Void)?
    var onLoadFinished: (() -> Void)?
    var onInteractionChange: ((Bool) -> Void)?

    static func makeContentID(bookID: UUID, chapterOrder: Int) -> String {
        "\(bookID.uuidString)-\(chapterOrder)"
    }

    static func preloadChapterHTML(
        contentID: String,
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

    private static func makeCacheKey(contentID: String, styleSignature: String) -> String {
        "chapter:\(contentID)|\(styleSignature)"
    }
    
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
        userContentController.add(context.coordinator, name: "selectionDebug")
        userContentController.add(context.coordinator, name: "highlightTap")
        userContentController.add(context.coordinator, name: "contentLinkTap")
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
        context.coordinator.applySelectionMaintenanceModeIfNeeded(on: webView)
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
            let cachedHTML = Self.renderedHTMLCache.object(forKey: cacheKey as NSString)
            DebugLogger.info(
                "[HighlightNav] updateUIView: 签名变化，重新加载 HTML, " +
                "contentID=\(contentID), cacheHit=\(cachedHTML != nil), " +
                "highlightToken=\(highlightNavigationToken), highlightOffset=\(highlightTextOffset.map(String.init) ?? "nil")"
            )
            container.accessibilityHint = signature
            context.coordinator.prepareForNewLoad()
            let css = getMobileOptimizedCSS()
            if let cachedHTML {
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
        let textColor = isDarkMode ? "rgba(255, 255, 255, 0.85)" : "rgba(0, 0, 0, 0.86)"
        let linkColor = isDarkMode ? "#5aadff" : "#0066cc"
        let pageMargin = Int(pageMargins)

        return """
        :root {
            --reader-page-margin: \(pageMargin)px;
            --reader-vertical-padding: 20px;
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
            overflow-x: hidden;
            overflow-y: hidden;
            background-color: \(backgroundColor);
            color: \(textColor);
            font-family: 'SFUI', -apple-system, 'PingFang SC', 'Hiragino Sans GB', sans-serif;
            -webkit-font-smoothing: antialiased;
            -webkit-font-feature-settings: 'kern' 1, 'liga' 1;
            font-feature-settings: 'kern' 1, 'liga' 1;
            text-rendering: optimizeLegibility;
            text-size-adjust: 100%;
            -webkit-text-size-adjust: 100%;
            -webkit-overflow-scrolling: auto;
            overscroll-behavior-x: none;
        }

        body {
            font-size: \(Int(fontSize))px;
            line-height: \(lineHeight);
            margin: 0;
            width: 100vw;
            height: 100vh;
            padding: 0;
            -webkit-hyphenate-character: auto;
            -webkit-hyphens: auto;
            hyphens: auto;
        }

        .reader-content {
            max-width: 100%;
            height: 100%;
            margin: 0;
            padding: var(--reader-vertical-padding) 0;
            word-wrap: break-word;
            overflow-wrap: break-word;
            word-break: break-word;
            -webkit-column-width: 100vw;
            column-width: 100vw;
            -webkit-column-gap: 0;
            column-gap: 0;
            -webkit-column-fill: auto;
            column-fill: auto;
        }

        .reader-book-root {
            width: 100%;
            max-width: 100%;
            min-height: 100%;
            margin: 0;
            padding-left: var(--reader-page-margin);
            padding-right: var(--reader-page-margin);
        }

        .reader-generated-continuation {
            text-indent: 0 !important;
            margin-top: 1em;
            -webkit-column-break-inside: avoid;
            break-inside: avoid;
        }

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

        p {
            margin: 0 0 0.85em 0;
            text-align: justify;
            text-indent: 2em;
            letter-spacing: 0.01em;
            orphans: 2;
            widows: 2;
        }

        h1, h2, h3, h4, h5, h6 {
            font-weight: 700;
            margin: 1.4em 0 0.6em 0;
            line-height: 1.25;
            text-indent: 0;
            letter-spacing: -0.01em;
            -webkit-column-break-after: avoid;
            break-after: avoid;
        }

        h1 {
            font-size: 1.65em;
            padding-bottom: 0.25em;
        }

        h2 {
            font-size: 1.4em;
        }

        h3 {
            font-size: 1.2em;
        }

        h4 {
            font-size: 1.08em;
        }

        h5, h6 {
            font-size: 1em;
        }

        a {
            color: \(linkColor);
            text-decoration: none;
            word-break: break-all;
        }

        a:active {
            opacity: 0.7;
        }

        img {
            max-width: 100% !important;
            height: auto !important;
            display: block;
            margin: 0.8em auto;
            border-radius: 4px;
            -webkit-column-break-inside: avoid;
            break-inside: avoid;
        }

        ul, ol {
            margin: 0.5em 0 0.5em 1.5em;
            padding-left: 1em !important;
        }

        li {
            margin: 0.25em 0;
        }

        blockquote {
            margin: 0.8em 0;
            padding: 0.6em 1em;
            border-left: 3px solid \(isDarkMode ? "rgba(255,255,255,0.15)" : "rgba(0,0,0,0.12)");
            background-color: \(isDarkMode ? "rgba(255,255,255,0.03)" : "rgba(0,0,0,0.02)");
            font-style: italic;
            -webkit-column-break-inside: avoid;
            break-inside: avoid;
        }

        code {
            font-family: 'SF Mono', 'Menlo', 'Monaco', monospace;
            font-size: 0.88em;
            padding: 0.15em 0.35em;
            background-color: \(isDarkMode ? "rgba(255,255,255,0.06)" : "rgba(0,0,0,0.04)");
            border-radius: 4px;
        }

        pre {
            margin: 0.8em 0;
            padding: 0.8em 1em;
            background-color: \(isDarkMode ? "rgba(255,255,255,0.05)" : "rgba(0,0,0,0.03)");
            border-radius: 6px;
            overflow-x: auto;
            -webkit-overflow-scrolling: touch;
            -webkit-column-break-inside: avoid;
            break-inside: avoid;
        }

        pre code {
            padding: 0;
            background-color: transparent;
        }

        table {
            width: 100%;
            max-width: 100%;
            border-collapse: collapse;
            margin: 0.8em 0;
            display: block;
            overflow-x: auto;
            -webkit-overflow-scrolling: touch;
            -webkit-column-break-inside: avoid;
            break-inside: avoid;
        }

        th, td {
            padding: 0.45em 0.6em;
            border: 1px solid \(isDarkMode ? "rgba(255,255,255,0.1)" : "rgba(0,0,0,0.08)");
            text-align: left;
        }

        th {
            background-color: \(isDarkMode ? "rgba(255,255,255,0.05)" : "rgba(0,0,0,0.03)");
            font-weight: 600;
        }

        hr {
            border: none;
            border-top: 1px solid \(isDarkMode ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.06)");
            margin: 1.8em 0;
        }

        strong, b {
            font-weight: 600;
        }

        em, i {
            font-style: italic;
        }

        del, s {
            text-decoration: line-through;
        }

        u {
            text-decoration: underline;
            text-underline-offset: 0.15em;
        }

        small {
            font-size: 0.85em;
        }

        div, article, section, aside, nav, header, footer, main {
            max-width: 100%;
            word-wrap: break-word;
        }

        pre, code, kbd, samp {
            white-space: pre-wrap;
            word-wrap: break-word;
        }

        svg {
            max-width: 100%;
            height: auto;
        }

        ::selection {
            background-color: \(isDarkMode ? "rgba(50, 130, 246, 0.35)" : "rgba(0, 122, 255, 0.2)");
            color: inherit;
        }

        mark.reader-highlight {
            background-color: \(isDarkMode ? "rgba(255, 214, 10, 0.25)" : "rgba(255, 230, 80, 0.45)");
            border-radius: 2px;
            padding: 0 1px !important;
            -webkit-box-decoration-break: clone;
            box-decoration-break: clone;
        }

        iframe {
            max-width: 100%;
        }

        .pagebreak {
            page-break-after: always;
            margin: 2em 0;
        }

        .footnote {
            font-size: 0.85em;
            vertical-align: super;
        }

        .no-select {
            -webkit-user-select: none;
            user-select: none;
        }
        """
    }
    
    private func getJavaScriptCode() -> String {
        let isIPhoneIdiom = UIDevice.current.userInterfaceIdiom == .phone
        return """
        function normalizeColor(colorHex) {
            if (!colorHex) return '#ffe38f';
            if (colorHex.startsWith('#')) { return colorHex; }
            return '#' + colorHex;
        }

        var isIPhoneSelectionOverlayFallbackEnabled = \(isIPhoneIdiom ? "true" : "false");
        var lastInteractionState = false;
        var touchPanStartX = 0;
        var touchPanStartY = 0;
        var selectionLockedPageIndex = null;
        var isRestoringSelectionPage = false;
        var selectionHardLockEnabled = false;
        var selectionHardLockUnlockDepth = 0;
        var isContinuingSelectionToNextPage = false;
        var lastStableSelectionPayload = null;
        var continuedSelectionAnchorOffset = null;
        var continuedSelectionNativeStartOffset = null;
        var continuedSelectionNativeEndOffset = null;
        var isRepairingContinuedNativeSelection = false;
        var isRestoringNativeSelectionRect = false;
        var nativeSelectionVisibilityMissCount = 0;
        var nativeSelectionLightRestoreAttemptedSignature = null;
        var nativeSelectionVisualRefreshAttemptedSignature = null;
        var isNativeSelectionVisualRefreshPending = false;
        var splitTailForceRefreshAttemptedSignature = null;
        var splitTailForceRefreshLastAt = 0;
        var isForcingSplitTailNativeRefresh = false;
        var lastStableNativeSelectionSnapshot = null;
        var pendingContinuationSelection = null;
        var selectionVisualOverlay = null;
        var selectionVisualHighlight = null;
        var selectionVisualStartHandle = null;
        var selectionVisualEndHandle = null;
        var selectionVisualOverlayVisible = false;
        var selectionVisualOverlayLastReason = '';
        var selectionVisualOverlayLastRectSource = '';
        var currentHorizontalOverflowMode = null;
        var lastReaderHorizontalDragLogAt = 0;
        var isApplyingPaginationLayout = false;
        var isSelectionMaintenanceSuspended = false;
        var lastSelectionMaintenanceSuspendLogAt = 0;

        function postSelectionDebugLog(label, details) {
            try {
                window.webkit.messageHandlers.selectionDebug.postMessage({
                    label: String(label || ''),
                    details: String(details || '')
                });
            } catch (e) {
                try { console.log('[SelectionDebug] ' + label + ' ' + details); } catch (ignore) {}
            }
        }

        function normalizeOverflowMode(mode) {
            // Keep horizontal scrolling fully locked to eliminate native slider + drift.
            return 'hidden';
        }

        function resolveSelectionLockMode() {
            if (selectionHardLockEnabled) { return 'hard'; }
            if (selectionLockedPageIndex !== null) { return 'soft'; }
            return 'none';
        }

        function describeRect(rect) {
            const x = Number(rect && rect.x);
            const y = Number(rect && rect.y);
            const width = Number(rect && rect.width);
            const height = Number(rect && rect.height);
            const safeX = Number.isFinite(x) ? x : 0;
            const safeY = Number.isFinite(y) ? y : 0;
            const safeWidth = Number.isFinite(width) ? width : 0;
            const safeHeight = Number.isFinite(height) ? height : 0;
            return '(' + safeX + ',' + safeY + ',' + safeWidth + ',' + safeHeight + ')';
        }

        function resolvePayloadRectSource(payload) {
            if (!payload) { return 'unknown'; }
            if (payload.rectSource === 'fallback') { return 'fallback'; }
            if (payload.rectSource === 'native') { return 'native'; }
            return 'unknown';
        }

        function getNativeSelectionRangeCount() {
            try {
                const selection = window.getSelection ? window.getSelection() : null;
                return selection ? selection.rangeCount : 0;
            } catch (e) {
                return 0;
            }
        }

        function resolveCurrentHorizontalOverflowMode() {
            if (currentHorizontalOverflowMode !== null) {
                return normalizeOverflowMode(currentHorizontalOverflowMode);
            }
            try {
                const documentMode = document.documentElement && document.documentElement.style
                    ? document.documentElement.style.overflowX
                    : '';
                const bodyMode = document.body && document.body.style ? document.body.style.overflowX : '';
                return normalizeOverflowMode(documentMode || bodyMode || 'hidden');
            } catch (e) {
                return 'hidden';
            }
        }

        function describeSelectionPayload(payload) {
            if (!payload) { return 'nil'; }
            const text = payload.text || '';
            const rectSource = resolvePayloadRectSource(payload);
            return 'len=' + text.length +
                ',start=' + payload.start +
                ',end=' + payload.end +
                ',page=' + payload.pageIndex +
                ',continue=' + (!!payload.canContinueToNextPage) +
                ',splitTail=' + (!!payload.isSplitParagraphTailRegion) +
                ',rect=' + describeRect(payload.rect) +
                ',rectSource=' + rectSource +
                ',lockMode=' + resolveSelectionLockMode() +
                ',preview=' + JSON.stringify(text.substring(0, 40));
        }

        function describeNativeSelectionState() {
            try {
                const selection = window.getSelection ? window.getSelection() : null;
                if (!selection) { return 'selection=nil'; }
                const text = selection.toString ? selection.toString() : '';
                const payload = serializeSelection();
                return 'rangeCount=' + selection.rangeCount +
                    ',textLen=' + text.length +
                    ',payload=' + describeSelectionPayload(payload);
            } catch (e) {
                return 'error=' + String(e);
            }
        }

        function maybeLogReaderHorizontalDrag(dx, dy, sourceTag, prevented) {
            const absDx = Math.abs(Number(dx) || 0);
            const absDy = Math.abs(Number(dy) || 0);
            if (absDx <= absDy + 4) { return; }

            const now = Date.now();
            if (now - lastReaderHorizontalDragLogAt < 80) { return; }
            lastReaderHorizontalDragLogAt = now;

            const splitTail = !!(lastStableSelectionPayload && lastStableSelectionPayload.isSplitParagraphTailRegion);
            postSelectionDebugLog(
                'selection.readerview.horizontalDrag',
                'source=' + String(sourceTag || 'unknown') +
                ',dx=' + dx +
                ',dy=' + dy +
                ',prevented=' + (!!prevented) +
                ',splitTail=' + splitTail +
                ',lockMode=' + resolveSelectionLockMode()
            );
        }

        function setHorizontalOverflowMode(mode, sourceTag) {
            const resolvedMode = normalizeOverflowMode(mode);
            const previousMode = resolveCurrentHorizontalOverflowMode();
            document.documentElement.style.overflowX = resolvedMode;
            document.body.style.overflowX = resolvedMode;
            document.documentElement.style.overflowY = 'hidden';
            document.body.style.overflowY = 'hidden';
            currentHorizontalOverflowMode = resolvedMode;
            if (previousMode !== resolvedMode) {
                postSelectionDebugLog(
                    'selection.overflow.modeSwitch',
                    'from=' + previousMode +
                    ',to=' + resolvedMode +
                    ',source=' + String(sourceTag || 'unknown') +
                    ',lockMode=' + resolveSelectionLockMode()
                );
            }
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

        function hideSelectionVisualOverlay(reason, payload) {
            const hideReason = String(reason || 'unspecified');
            const rectSource = resolvePayloadRectSource(payload);
            const wasVisible = selectionVisualOverlayVisible;
            if (selectionVisualOverlay) {
                selectionVisualOverlay.style.display = 'none';
            }
            selectionVisualOverlayVisible = false;
            if (
                wasVisible ||
                selectionVisualOverlayLastReason !== hideReason ||
                selectionVisualOverlayLastRectSource !== rectSource
            ) {
                postSelectionDebugLog(
                    'selection.overlay.hide',
                    'reason=' + hideReason +
                    ',rectSource=' + rectSource +
                    ',lockMode=' + resolveSelectionLockMode()
                );
            }
            selectionVisualOverlayLastReason = hideReason;
            selectionVisualOverlayLastRectSource = rectSource;
        }

        function updateSelectionVisualOverlay(payload) {
            const isContinuationOverlay = continuedSelectionAnchorOffset !== null;
            if (!selectionHasText(payload)) {
                hideSelectionVisualOverlay('emptySelection', payload);
                return;
            }

            const rect = payload && payload.rect ? payload.rect : null;
            if (!rect) {
                hideSelectionVisualOverlay('missingRect', payload);
                return;
            }

            const splitTailForOverlay = !!(payload && payload.isSplitParagraphTailRegion);
            const shouldUseIPhoneFallbackOverlay =
                isIPhoneSelectionOverlayFallbackEnabled &&
                (
                    splitTailForOverlay ||
                    nativeSelectionVisibilityMissCount >= 1 ||
                    isSelectionRectClearlyInvalid(rect)
                );
            if (!isContinuationOverlay && !shouldUseIPhoneFallbackOverlay) {
                hideSelectionVisualOverlay('nativeLikelyVisible', payload);
                return;
            }

            const rawLeft = Number(rect.x);
            const rawTop = Number(rect.y);
            const rawWidth = Number(rect.width);
            const rawHeight = Number(rect.height);
            if (
                !Number.isFinite(rawLeft) ||
                !Number.isFinite(rawTop) ||
                !Number.isFinite(rawWidth) ||
                !Number.isFinite(rawHeight) ||
                rawWidth <= 1 ||
                rawHeight <= 1 ||
                (rawWidth * rawHeight) <= 4
            ) {
                hideSelectionVisualOverlay('invalidRect', payload);
                return;
            }

            const viewportWidth = Math.max(1, window.innerWidth || document.documentElement.clientWidth || document.body.clientWidth || 1);
            const viewportHeight = Math.max(1, window.innerHeight || document.documentElement.clientHeight || document.body.clientHeight || 1);
            const clampedLeft = Math.max(0, Math.min(rawLeft, viewportWidth - 1));
            const clampedTop = Math.max(0, Math.min(rawTop, viewportHeight - 1));
            const visibleWidth = Math.max(0, Math.min(rawLeft + rawWidth, viewportWidth) - clampedLeft);
            const visibleHeight = Math.max(0, Math.min(rawTop + rawHeight, viewportHeight) - clampedTop);
            if (visibleWidth <= 1 || visibleHeight <= 1 || (visibleWidth * visibleHeight) <= 4) {
                hideSelectionVisualOverlay('rectOutsideViewport', payload);
                return;
            }

            ensureSelectionVisualOverlay();

            const handleSize = 14;
            const handleRadius = handleSize / 2;
            const handleY = Math.max(0, Math.min(viewportHeight - handleSize, clampedTop + visibleHeight - handleRadius));
            const startHandleX = Math.max(0, Math.min(viewportWidth - handleSize, clampedLeft - handleRadius));
            const endHandleX = Math.max(0, Math.min(viewportWidth - handleSize, clampedLeft + visibleWidth - handleRadius));
            // iPhone fallback overlay is visual-only; avoid fake draggable handles that
            // can mask or mislead against native iOS selection handles.
            const shouldShowOverlayHandles = isContinuationOverlay;

            selectionVisualHighlight.style.left = clampedLeft + 'px';
            selectionVisualHighlight.style.top = clampedTop + 'px';
            selectionVisualHighlight.style.width = visibleWidth + 'px';
            selectionVisualHighlight.style.height = visibleHeight + 'px';

            if (shouldShowOverlayHandles) {
                selectionVisualStartHandle.style.display = 'block';
                selectionVisualEndHandle.style.display = 'block';
                selectionVisualStartHandle.style.left = startHandleX + 'px';
                selectionVisualStartHandle.style.top = handleY + 'px';
                selectionVisualEndHandle.style.left = endHandleX + 'px';
                selectionVisualEndHandle.style.top = handleY + 'px';
            } else {
                selectionVisualStartHandle.style.display = 'none';
                selectionVisualEndHandle.style.display = 'none';
            }

            selectionVisualOverlay.style.display = 'block';
            const showReason = isContinuationOverlay ? 'continuationSelection' : 'iphoneFallbackOverlay';
            const rectSource = resolvePayloadRectSource(payload);
            if (
                !selectionVisualOverlayVisible ||
                selectionVisualOverlayLastReason !== showReason ||
                selectionVisualOverlayLastRectSource !== rectSource
            ) {
                postSelectionDebugLog(
                    'selection.overlay.show',
                    'reason=' + showReason +
                    ',rectSource=' + rectSource +
                    ',handles=' + (shouldShowOverlayHandles ? 'yes' : 'no') +
                    ',miss=' + nativeSelectionVisibilityMissCount +
                    ',lockMode=' + resolveSelectionLockMode()
                );
            }
            selectionVisualOverlayVisible = true;
            selectionVisualOverlayLastReason = showReason;
            selectionVisualOverlayLastRectSource = rectSource;
        }

        function scheduleNativeSelectionVisualRefresh(nativePayload, reasonTag) {
            if (!isIPhoneSelectionOverlayFallbackEnabled) { return; }
            if (continuedSelectionAnchorOffset !== null) { return; }
            if (!selectionHasText(nativePayload)) { return; }
            if (isNativeSelectionVisualRefreshPending) { return; }

            const signature = buildNativeSelectionSignature(
                nativePayload.start,
                nativePayload.end,
                nativePayload.pageIndex
            );
            if (!signature) { return; }
            if (nativeSelectionVisualRefreshAttemptedSignature === signature) { return; }

            nativeSelectionVisualRefreshAttemptedSignature = signature;
            isNativeSelectionVisualRefreshPending = true;
            const reason = String(reasonTag || 'unknown');
            postSelectionDebugLog(
                'selection.nativeVisualRefresh.begin',
                'reason=' + reason +
                ',sig=' + signature +
                ',state=' + describeNativeSelectionState()
            );

            requestAnimationFrame(function() {
                try {
                    withSelectionHardLockTemporarilyDisabled(function() {
                        const originalScrollLeft = getScrollLeft();
                        const perPage = getPerPage();
                        const maxScrollLeft = Math.max(0, getTotalWidth() - perPage);
                        let nudgedScrollLeft = originalScrollLeft;

                        if (maxScrollLeft > 0) {
                            if (originalScrollLeft + 1 <= maxScrollLeft) {
                                nudgedScrollLeft = originalScrollLeft + 1;
                            } else if (originalScrollLeft - 1 >= 0) {
                                nudgedScrollLeft = originalScrollLeft - 1;
                            }
                        }

                        if (nudgedScrollLeft !== originalScrollLeft) {
                            setScrollLeft(nudgedScrollLeft, false, 'nativeVisualRefresh.nudge');
                            setScrollLeft(originalScrollLeft, false, 'nativeVisualRefresh.restore');
                        } else {
                            // Fallback to forced layout flush when scrolling cannot move.
                            void document.body.offsetHeight;
                        }
                    }, 'nativeVisualRefresh');
                } catch (e) {} finally {
                    isNativeSelectionVisualRefreshPending = false;
                    postSelectionDebugLog(
                        'selection.nativeVisualRefresh.end',
                        'reason=' + reason +
                        ',sig=' + signature +
                        ',state=' + describeNativeSelectionState()
                    );
                    setTimeout(function() {
                        notifySelectionChange();
                    }, 0);
                }
            });
        }

        function withSelectionHardLockTemporarilyDisabled(work, sourceTag) {
            selectionHardLockUnlockDepth += 1;
            try {
                return work();
            } finally {
                selectionHardLockUnlockDepth = Math.max(0, selectionHardLockUnlockDepth - 1);
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

        function resolveCollapsedSelectionBoundaryRect(node, offset) {
            if (!node) { return null; }
            const probeRange = document.createRange();
            try {
                let resolvedNode = node;
                let resolvedOffset = Number.isFinite(offset) ? Math.floor(offset) : 0;
                if (resolvedNode.nodeType === Node.TEXT_NODE) {
                    const textLength = (resolvedNode.textContent || '').length;
                    resolvedOffset = Math.max(0, Math.min(resolvedOffset, textLength));
                } else {
                    const childCount = resolvedNode.childNodes ? resolvedNode.childNodes.length : 0;
                    resolvedOffset = Math.max(0, Math.min(resolvedOffset, childCount));
                }

                probeRange.setStart(resolvedNode, resolvedOffset);
                probeRange.setEnd(resolvedNode, resolvedOffset);

                let resolvedRect = null;
                const collapsedRects = probeRange.getClientRects ? probeRange.getClientRects() : null;
                if (collapsedRects && collapsedRects.length > 0) {
                    resolvedRect = collapsedRects[0];
                }

                // Collapsed ranges may report zero-size rect on iOS. Probe one adjacent
                // character to recover a stable line rect near the drag handle.
                if (
                    (!resolvedRect || safeNumber(resolvedRect.height, 0) <= 1 || safeNumber(resolvedRect.width, 0) <= 0) &&
                    resolvedNode.nodeType === Node.TEXT_NODE
                ) {
                    const text = resolvedNode.textContent || '';
                    const textLength = text.length;
                    if (textLength > 0) {
                        const charStart = Math.max(0, Math.min(resolvedOffset, textLength - 1));
                        const charEnd = Math.min(textLength, charStart + 1);
                        if (charEnd > charStart) {
                            probeRange.setStart(resolvedNode, charStart);
                            probeRange.setEnd(resolvedNode, charEnd);
                            const charRects = probeRange.getClientRects ? probeRange.getClientRects() : null;
                            if (charRects && charRects.length > 0) {
                                resolvedRect = charRects[0];
                            }
                        }
                    }
                }

                if (!resolvedRect && probeRange.getBoundingClientRect) {
                    resolvedRect = probeRange.getBoundingClientRect();
                }
                if (!resolvedRect) { return null; }

                return {
                    x: safeNumber(resolvedRect.x, 0),
                    y: safeNumber(resolvedRect.y, 0),
                    width: safeNumber(resolvedRect.width, 0),
                    height: safeNumber(resolvedRect.height, 0)
                };
            } catch (e) {
                return null;
            } finally {
                try { probeRange.detach(); } catch (ignore) {}
            }
        }

        function resolveSelectionRect(range, selection) {
            if (!range) {
                return { x: 0, y: 0, width: 0, height: 0, source: 'none' };
            }

            const viewportWidth = Math.max(1, window.innerWidth || document.documentElement.clientWidth || document.body.clientWidth || 1);
            const viewportHeight = Math.max(1, window.innerHeight || document.documentElement.clientHeight || document.body.clientHeight || 1);
            const viewportTop = 0;
            const viewportLeft = 0;
            const viewportBottom = viewportHeight;
            const viewportRight = viewportWidth;

            const focusNode = selection && selection.focusNode ? selection.focusNode : null;
            const focusOffset = selection && Number.isFinite(selection.focusOffset) ? selection.focusOffset : null;
            const focusRect = resolveCollapsedSelectionBoundaryRect(
                focusNode || range.endContainer,
                focusOffset !== null ? focusOffset : range.endOffset
            );
            if (focusRect) {
                const focusVisibleWidth = Math.max(0, Math.min(focusRect.x + focusRect.width, viewportRight) - Math.max(focusRect.x, viewportLeft));
                const focusVisibleHeight = Math.max(0, Math.min(focusRect.y + focusRect.height, viewportBottom) - Math.max(focusRect.y, viewportTop));
                const focusVisibleScore = focusVisibleWidth * focusVisibleHeight;
                if (focusVisibleScore > 4) {
                    return {
                        x: focusRect.x,
                        y: focusRect.y,
                        width: focusRect.width,
                        height: focusRect.height,
                        source: 'focus'
                    };
                }
            }

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
                    bestRect = { x: x, y: y, width: width, height: height, source: 'native' };
                }
            });

            if (!bestRect) {
                const fallbackRect = range.getBoundingClientRect();
                bestRect = fallbackRect ? {
                    x: safeNumber(fallbackRect.x, 0),
                    y: safeNumber(fallbackRect.y, 0),
                    width: safeNumber(fallbackRect.width, 0),
                    height: safeNumber(fallbackRect.height, 0),
                    source: 'fallback'
                } : { x: 0, y: 0, width: 0, height: 0, source: 'none' };
            }

            return bestRect;
        }

        function sanitizeSelectionTextForFootnotes(rawText) {
            var text = typeof rawText === 'string' ? rawText : '';
            if (!text) { return ''; }

            // Remove superscript citation digits (e.g. ¹²³) attached to selected text.
            text = text.replace(/(\\S)[⁰¹²³⁴⁵⁶⁷⁸⁹]+/g, '$1');
            // Remove bracket citation markers attached to text (e.g. word[12], word(12)).
            text = text.replace(/(\\S)(?:\\[\\s*\\d{1,3}\\s*\\]|\\(\\s*\\d{1,3}\\s*\\))/g, '$1');
            // Remove attached citation lists (e.g. path.3,4,5,6).
            text = text.replace(/(\\S)(?:\\d{1,3}\\s*[,，]\\s*)+\\d{1,3}(?=\\s|$|[)\\]}"'”’.,;:!?。！？；：])/g, '$1');
            // Remove a single trailing citation marker when it follows sentence punctuation.
            text = text.replace(/([^\\d][.!?。！？:;；])\\s*\\d{1,3}(?=\\s|$|[)\\]}"'”’.,;:!?。！？；：])/g, '$1');
            // Clean separators left behind after stripping link markers.
            text = text.replace(/(?:\\s*[,，]\\s*){2,}/g, ', ');
            text = text.replace(/(^|[\\s(\\[{])[,，\\s]+(?=\\s|$|[)\\]}.,;:!?。！？；：])/g, '$1');
            text = text.replace(/[ \\t]{2,}/g, ' ');
            return text.trim();
        }

        function extractSelectionTextWithoutFootnoteLinks(range, fallbackText) {
            var fallback = typeof fallbackText === 'string' ? fallbackText : '';
            if (!range || typeof range.cloneContents !== 'function') {
                return sanitizeSelectionTextForFootnotes(fallback);
            }

            var resolvedText = fallback;
            try {
                var fragment = range.cloneContents();
                if (fragment && fragment.querySelectorAll) {
                    var links = Array.from(fragment.querySelectorAll('a'));
                    links.forEach(function(link) {
                        if (!link || !hasFootnoteHint(link)) { return; }
                        var parent = link.parentNode;
                        if (parent && parent.nodeType === Node.ELEMENT_NODE) {
                            var tagName = String(parent.tagName || '').toLowerCase();
                            if ((tagName === 'sup' || tagName === 'sub') && parent.parentNode) {
                                parent.parentNode.removeChild(parent);
                                return;
                            }
                        }
                        if (parent) {
                            parent.removeChild(link);
                        }
                    });
                }
                resolvedText = fragment && typeof fragment.textContent === 'string'
                    ? fragment.textContent
                    : fallback;
            } catch (e) {
                resolvedText = fallback;
            }
            return sanitizeSelectionTextForFootnotes(resolvedText);
        }

        function serializeSelection() {
            const selection = window.getSelection();
            if (!selection || selection.rangeCount === 0) {
                return null;
            }

            const range = selection.getRangeAt(0);
            const text = selection.toString ? selection.toString() : '';
            const cleanedText = extractSelectionTextWithoutFootnoteLinks(range, text);
            const rect = resolveSelectionRect(range, selection);
            const start = measureOffset(range.startContainer, range.startOffset);
            const end = measureOffset(range.endContainer, range.endOffset);
            const safeStart = Math.min(start, end);
            const safeEnd = Math.max(start, end);
            const pageIndex = Math.max(0, Math.round(getScrollLeft() / getPerPage()));

            return {
                text: text,
                cleanedText: cleanedText,
                start: safeStart,
                end: safeEnd,
                pageIndex: pageIndex,
                rectSource: rect.source === 'fallback' ? 'fallback' : 'native',
                rect: {
                    x: rect.x,
                    y: rect.y,
                    width: rect.width,
                    height: rect.height
                },
                isSplitParagraphTailRegion: false
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
                cleanedText: payload.cleanedText || '',
                start: typeof payload.start === 'number' ? payload.start : 0,
                end: typeof payload.end === 'number' ? payload.end : 0,
                pageIndex: typeof payload.pageIndex === 'number' ? payload.pageIndex : 0,
                rect: {
                    x: payload.rect && typeof payload.rect.x === 'number' ? payload.rect.x : 0,
                    y: payload.rect && typeof payload.rect.y === 'number' ? payload.rect.y : 0,
                    width: payload.rect && typeof payload.rect.width === 'number' ? payload.rect.width : 0,
                    height: payload.rect && typeof payload.rect.height === 'number' ? payload.rect.height : 0
                },
                rectSource: payload.rectSource === 'fallback' ? 'fallback' : 'native',
                canContinueToNextPage: !!payload.canContinueToNextPage,
                isSplitParagraphTailRegion: !!payload.isSplitParagraphTailRegion
            };
        }

        function cloneSelectionRect(rect) {
            return {
                x: rect && typeof rect.x === 'number' ? rect.x : 0,
                y: rect && typeof rect.y === 'number' ? rect.y : 0,
                width: rect && typeof rect.width === 'number' ? rect.width : 0,
                height: rect && typeof rect.height === 'number' ? rect.height : 0
            };
        }

        function buildNativeSelectionSignature(start, end, pageIndex) {
            if (typeof start !== 'number' || typeof end !== 'number') { return ''; }
            if (!(end > start)) { return ''; }
            const safePageIndex = typeof pageIndex === 'number' ? pageIndex : -1;
            return String(safePageIndex) + ':' + String(start) + '-' + String(end);
        }

        function isSelectionRectClearlyInvalid(rect) {
            if (!rect) { return true; }
            const x = Number(rect.x);
            const y = Number(rect.y);
            const width = Number(rect.width);
            const height = Number(rect.height);
            if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(width) || !Number.isFinite(height)) {
                return true;
            }
            if (width <= 1 || height <= 1 || (width * height) <= 4) { return true; }

            const viewportWidth = Math.max(1, window.innerWidth || document.documentElement.clientWidth || document.body.clientWidth || 1);
            const viewportHeight = Math.max(1, window.innerHeight || document.documentElement.clientHeight || document.body.clientHeight || 1);
            if (width > viewportWidth * 3 || height > viewportHeight * 3) { return true; }
            if ((x + width) < -24 || x > (viewportWidth + 24) || (y + height) < -24 || y > (viewportHeight + 24)) {
                return true;
            }
            return false;
        }

        function hasStableVisibleSelectionRect(rect) {
            if (isSelectionRectClearlyInvalid(rect)) { return false; }
            const x = Number(rect.x);
            const y = Number(rect.y);
            const width = Number(rect.width);
            const height = Number(rect.height);
            const viewportWidth = Math.max(1, window.innerWidth || document.documentElement.clientWidth || document.body.clientWidth || 1);
            const viewportHeight = Math.max(1, window.innerHeight || document.documentElement.clientHeight || document.body.clientHeight || 1);
            const visibleWidth = Math.max(0, Math.min(x + width, viewportWidth) - Math.max(x, 0));
            const visibleHeight = Math.max(0, Math.min(y + height, viewportHeight) - Math.max(y, 0));
            return visibleWidth > 1 && visibleHeight > 1 && (visibleWidth * visibleHeight) > 4;
        }

        function recordStableNativeSelectionSnapshot(nativePayload) {
            if (!selectionHasText(nativePayload)) { return; }
            lastStableNativeSelectionSnapshot = {
                start: typeof nativePayload.start === 'number' ? nativePayload.start : 0,
                end: typeof nativePayload.end === 'number' ? nativePayload.end : 0,
                pageIndex: typeof nativePayload.pageIndex === 'number' ? nativePayload.pageIndex : 0,
                rect: cloneSelectionRect(nativePayload.rect)
            };
        }

        function resolveNativeSelectionRestoreOffsets(nativePayload) {
            if (
                nativePayload &&
                typeof nativePayload.start === 'number' &&
                typeof nativePayload.end === 'number' &&
                nativePayload.end > nativePayload.start
            ) {
                return {
                    start: nativePayload.start,
                    end: nativePayload.end
                };
            }
            if (
                lastStableNativeSelectionSnapshot &&
                typeof lastStableNativeSelectionSnapshot.start === 'number' &&
                typeof lastStableNativeSelectionSnapshot.end === 'number' &&
                lastStableNativeSelectionSnapshot.end > lastStableNativeSelectionSnapshot.start
            ) {
                return {
                    start: lastStableNativeSelectionSnapshot.start,
                    end: lastStableNativeSelectionSnapshot.end
                };
            }
            return null;
        }

        function attemptLightNativeSelectionRestore(nativePayload, segments, keepHardLockAfterRestore, sourceTag) {
            const restoreOffsets = resolveNativeSelectionRestoreOffsets(nativePayload);
            if (!restoreOffsets) { return nativePayload; }

            const shouldRestoreSoftLockAfterRestore =
                !selectionHardLockEnabled &&
                !keepHardLockAfterRestore;
            const restoreSource = String(sourceTag || 'unknown');
            const beforeState = describeNativeSelectionState();

            var restoredNativePayload = nativePayload;
            var restoreSucceeded = false;
            setSelectionHardLock(true, restoreSource);
            try {
                var restoreSegments = buildTextSegments();
                if (!restoreSegments || restoreSegments.length === 0) {
                    restoreSegments = segments || [];
                }
                var restored = applyNativeSelectionRange(
                    restoreOffsets.start,
                    restoreOffsets.end,
                    restoreSegments
                );
                if (restored) {
                    var serialized = serializeSelection();
                    if (selectionHasText(serialized)) {
                        restoredNativePayload = serialized;
                        restoreSucceeded = true;
                    }
                }
            } catch (e) {} finally {
                if (shouldRestoreSoftLockAfterRestore) {
                    setSelectionHardLock(false, restoreSource);
                }
            }
            postSelectionDebugLog(
                'selection.restore.execute',
                'source=' + restoreSource +
                ',success=' + restoreSucceeded +
                ',offsets=' + restoreOffsets.start + '-' + restoreOffsets.end +
                ',before=' + beforeState +
                ',after=' + describeNativeSelectionState()
            );
            return restoredNativePayload;
        }

        function maybeForceSplitTailNativeSelectionRefresh(nativePayload, segments, sourceTag) {
            if (!isIPhoneSelectionOverlayFallbackEnabled) { return nativePayload; }
            if (isForcingSplitTailNativeRefresh) { return nativePayload; }
            if (!selectionHasText(nativePayload)) { return nativePayload; }
            if (continuedSelectionAnchorOffset !== null) { return nativePayload; }
            if (!detectSplitParagraphTailSelection(nativePayload, segments)) { return nativePayload; }

            const signature = buildNativeSelectionSignature(
                nativePayload.start,
                nativePayload.end,
                nativePayload.pageIndex
            );
            if (!signature) { return nativePayload; }

            const now = Date.now();
            if (
                splitTailForceRefreshAttemptedSignature === signature &&
                (now - splitTailForceRefreshLastAt) < 240
            ) {
                return nativePayload;
            }
            splitTailForceRefreshAttemptedSignature = signature;
            splitTailForceRefreshLastAt = now;

            const refreshSource = String(sourceTag || 'selectionChange');
            postSelectionDebugLog(
                'selection.splitTail.forceRefresh.begin',
                'source=' + refreshSource +
                ',sig=' + signature +
                ',state=' + describeNativeSelectionState()
            );

            let refreshedNativePayload = nativePayload;
            isForcingSplitTailNativeRefresh = true;
            try {
                const keepHardLockAfterRestore =
                    selectionHardLockEnabled ||
                    isContinuingSelectionToNextPage ||
                    continuedSelectionAnchorOffset !== null;
                refreshedNativePayload = attemptLightNativeSelectionRestore(
                    nativePayload,
                    segments,
                    keepHardLockAfterRestore,
                    'splitTailForceRefresh'
                );
            } finally {
                isForcingSplitTailNativeRefresh = false;
            }

            postSelectionDebugLog(
                'selection.splitTail.forceRefresh.end',
                'source=' + refreshSource +
                ',sig=' + signature +
                ',payload=' + describeSelectionPayload(refreshedNativePayload)
            );
            return refreshedNativePayload;
        }

        function extractTextFromOffsets(startOffset, endOffset, segments) {
            const range = buildRangeFromOffsets(startOffset, endOffset, segments);
            if (!range) { return ''; }
            const text = range.toString ? range.toString() : '';
            range.detach();
            return text || '';
        }

        function extractCleanedTextFromOffsets(startOffset, endOffset, segments) {
            const range = buildRangeFromOffsets(startOffset, endOffset, segments);
            if (!range) { return ''; }
            const fallbackText = range.toString ? range.toString() : '';
            const cleaned = extractSelectionTextWithoutFootnoteLinks(range, fallbackText);
            range.detach();
            return cleaned || '';
        }

        function focusReaderDocument() {
            if (isSelectionMaintenanceSuspended) { return; }
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

            postSelectionDebugLog(
                'applyNativeSelectionRange',
                'start=' + startOffset +
                ',end=' + endOffset +
                ',applied=' + applied +
                ',state=' + describeNativeSelectionState()
            );
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
            const combinedCleanedText = extractCleanedTextFromOffsets(combinedStart, combinedEnd, resolvedSegments);
            payload.text = combinedText || payload.text;
            payload.cleanedText = combinedCleanedText || payload.cleanedText;
            payload.start = combinedStart;
            payload.end = combinedEnd;
            return payload;
        }

        function getTotalPageCount() {
            const totalWidth = getTotalWidth();
            const perPage = getPerPage();
            return Math.max(1, Math.ceil(totalWidth / perPage));
        }

        function setSelectionHardLock(enabled, sourceTag) {
            selectionHardLockEnabled = !!enabled;
        }

        function clearSelectionLockState() {
            selectionLockedPageIndex = null;
            lastStableSelectionPayload = null;
            continuedSelectionAnchorOffset = null;
            continuedSelectionNativeStartOffset = null;
            continuedSelectionNativeEndOffset = null;
            isRestoringNativeSelectionRect = false;
            nativeSelectionVisibilityMissCount = 0;
            nativeSelectionLightRestoreAttemptedSignature = null;
            nativeSelectionVisualRefreshAttemptedSignature = null;
            isNativeSelectionVisualRefreshPending = false;
            splitTailForceRefreshAttemptedSignature = null;
            splitTailForceRefreshLastAt = 0;
            isForcingSplitTailNativeRefresh = false;
            lastStableNativeSelectionSnapshot = null;
            setSelectionHardLock(false, 'clearSelectionLockState');
        }

        function setSelectionMaintenanceSuspended(suspended, sourceTag) {
            const next = !!suspended;
            if (isSelectionMaintenanceSuspended === next) {
                return false;
            }
            isSelectionMaintenanceSuspended = next;
            postSelectionDebugLog(
                'selection.maintenance.mode',
                'suspended=' + next +
                ',source=' + String(sourceTag || 'unknown') +
                ',state=' + describeNativeSelectionState()
            );
            if (!next) {
                notifySelectionChange();
            }
            return true;
        }

        function enforceSelectionLockedPageIfNeeded() {
            if (selectionLockedPageIndex === null || isRestoringSelectionPage || isContinuingSelectionToNextPage) { return; }
            const currentPage = Math.max(0, Math.round(getScrollLeft() / getPerPage()));
            if (currentPage === selectionLockedPageIndex) { return; }
            setSelectionHardLock(true, 'enforceSelectionLockedPage');
            isRestoringSelectionPage = true;
            scrollToPage(selectionLockedPageIndex, false, 'enforceSelectionLockedPage');
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

        function detectSplitParagraphTailSelection(nativePayload, segments) {
            if (!nativePayload || !segments || segments.length === 0) { return false; }
            if (typeof nativePayload.start !== 'number' || typeof nativePayload.end !== 'number') { return false; }
            if (!(nativePayload.end > nativePayload.start)) { return false; }

            const startBoundary = locateOffsetBoundary(nativePayload.start, segments, true);
            if (!startBoundary || !startBoundary.node) { return false; }
            const paragraphContainer = resolveParagraphContainer(startBoundary.node);
            if (!paragraphContainer) { return false; }

            let paragraphStartOffset = null;
            for (let i = 0; i < segments.length; i += 1) {
                const segment = segments[i];
                if (!segment || !segment.node) { continue; }
                if (paragraphContainer.contains(segment.node)) {
                    paragraphStartOffset = segment.start;
                    break;
                }
            }

            if (paragraphStartOffset === null) { return false; }
            if (nativePayload.start <= paragraphStartOffset) { return false; }

            const paragraphStartPage = estimatePageIndexForOffset(paragraphStartOffset, segments);
            const selectionStartPage = estimatePageIndexForOffset(nativePayload.start, segments);
            if (paragraphStartPage === null || selectionStartPage === null) { return false; }
            return paragraphStartPage < selectionStartPage;
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
            if (isSelectionMaintenanceSuspended) {
                const now = Date.now();
                if (now - lastSelectionMaintenanceSuspendLogAt > 300) {
                    lastSelectionMaintenanceSuspendLogAt = now;
                    postSelectionDebugLog(
                        'notifySelectionChange.suspended',
                        'state=' + describeNativeSelectionState()
                    );
                }
                return;
            }
            const pageIndex = Math.max(0, Math.round(getScrollLeft() / getPerPage()));
            const segments = buildTextSegments();
            let nativePayload = serializeSelection();
            let payload = null;
            if (selectionHasText(nativePayload)) {
                const isInitialLongPressSelection = selectionLockedPageIndex === null;
                if (isInitialLongPressSelection) {
                    postSelectionDebugLog(
                        'notifySelectionChange.initialLongPress',
                        'rangeCount=' + getNativeSelectionRangeCount() +
                        ',text.length=' + ((nativePayload.text || '').length) +
                        ',start=' + nativePayload.start +
                        ',end=' + nativePayload.end +
                        ',pageIndex=' + nativePayload.pageIndex +
                        ',rect=' + describeRect(nativePayload.rect) +
                        ',lockMode=' + resolveSelectionLockMode()
                    );
                }
                if (selectionLockedPageIndex === null) {
                    selectionLockedPageIndex = nativePayload.pageIndex;
                    // 初始长按仅软锁页（selectionLockedPageIndex）；横向滚动始终禁用。
                }

                const didDetectHorizontalDrift =
                    selectionLockedPageIndex !== null &&
                    nativePayload.pageIndex !== selectionLockedPageIndex &&
                    !isRestoringSelectionPage;

                if (didDetectHorizontalDrift) {
                    setSelectionHardLock(true, 'notifySelectionChange.native');
                    isRestoringSelectionPage = true;
                    scrollToPage(selectionLockedPageIndex, false, 'notifySelectionChange.native');
                    isRestoringSelectionPage = false;
                    const restoredPayload = serializeSelection();
                    if (selectionHasText(restoredPayload)) {
                        nativePayload = restoredPayload;
                    }
                }

                if (selectionLockedPageIndex !== null) {
                    nativePayload.pageIndex = selectionLockedPageIndex;
                }

                if (continuedSelectionAnchorOffset !== null) {
                    setSelectionHardLock(true, 'notifySelectionChange.native');
                }

                const nativeSignature = buildNativeSelectionSignature(
                    nativePayload.start,
                    nativePayload.end,
                    nativePayload.pageIndex
                );
                const nativeRectClearlyInvalid = isSelectionRectClearlyInvalid(nativePayload.rect);
                const nativeRectStableVisible = hasStableVisibleSelectionRect(nativePayload.rect);
                if (nativeRectStableVisible) {
                    nativeSelectionVisibilityMissCount = 0;
                    nativeSelectionLightRestoreAttemptedSignature = null;
                    recordStableNativeSelectionSnapshot(nativePayload);
                } else {
                    nativeSelectionVisibilityMissCount = Math.min(12, nativeSelectionVisibilityMissCount + 1);
                }

                const shouldRestoreForIPhoneUnstableVisibility =
                    isIPhoneSelectionOverlayFallbackEnabled &&
                    !nativeRectStableVisible &&
                    nativeSelectionVisibilityMissCount >= 3;
                const shouldAttemptLightRestore =
                    !!nativeSignature &&
                    !isRestoringNativeSelectionRect &&
                    nativeSelectionLightRestoreAttemptedSignature !== nativeSignature &&
                    (nativeRectClearlyInvalid || shouldRestoreForIPhoneUnstableVisibility);
                if (shouldAttemptLightRestore) {
                    nativeSelectionLightRestoreAttemptedSignature = nativeSignature;
                    const keepHardLockAfterRestore =
                        selectionHardLockEnabled ||
                        isContinuingSelectionToNextPage ||
                        continuedSelectionAnchorOffset !== null ||
                        didDetectHorizontalDrift;
                    const restoreReason = nativeRectClearlyInvalid ? 'invalidRect' : 'iphoneUnstableVisible';
                    postSelectionDebugLog(
                        'notifySelectionChange.native.lightRestore.begin',
                        'reason=' + restoreReason +
                        ',miss=' + nativeSelectionVisibilityMissCount +
                        ',sig=' + nativeSignature +
                        ',state=' + describeNativeSelectionState()
                    );
                    isRestoringNativeSelectionRect = true;
                    try {
                        nativePayload = attemptLightNativeSelectionRestore(
                            nativePayload,
                            segments,
                            keepHardLockAfterRestore,
                            'notifySelectionChange.native'
                        );
                    } finally {
                        isRestoringNativeSelectionRect = false;
                    }
                    if (selectionLockedPageIndex !== null) {
                        nativePayload.pageIndex = selectionLockedPageIndex;
                    }
                    if (hasStableVisibleSelectionRect(nativePayload.rect)) {
                        nativeSelectionVisibilityMissCount = 0;
                        nativeSelectionLightRestoreAttemptedSignature = null;
                        recordStableNativeSelectionSnapshot(nativePayload);
                    }
                    postSelectionDebugLog(
                        'notifySelectionChange.native.lightRestore.end',
                        'reason=' + restoreReason + ',payload=' + describeSelectionPayload(nativePayload)
                    );
                }

                const isSplitParagraphTailRegion = detectSplitParagraphTailSelection(nativePayload, segments);
                if (isSplitParagraphTailRegion) {
                    nativePayload = maybeForceSplitTailNativeSelectionRefresh(
                        nativePayload,
                        segments,
                        isInitialLongPressSelection ? 'initialLongPress' : 'selectionChange'
                    );
                    if (selectionLockedPageIndex !== null) {
                        nativePayload.pageIndex = selectionLockedPageIndex;
                    }
                }
                nativePayload.isSplitParagraphTailRegion = isSplitParagraphTailRegion;
                payload = buildEffectiveSelectionPayload(nativePayload, segments);
                payload.canContinueToNextPage = shouldOfferContinueSelectionToNextPage(payload);
                payload.isSplitParagraphTailRegion = isSplitParagraphTailRegion;
                continuedSelectionNativeStartOffset = nativePayload.start;
                continuedSelectionNativeEndOffset = nativePayload.end;
                lastStableSelectionPayload = cloneSelectionPayload(payload);
                updateSelectionVisualOverlay(payload);
                postSelectionDebugLog('notifySelectionChange.native', describeSelectionPayload(payload));
            } else {
                const currentPage = Math.max(0, Math.round(getScrollLeft() / getPerPage()));
                nativeSelectionVisibilityMissCount = 0;
                const didDetectHorizontalDrift =
                    selectionLockedPageIndex !== null &&
                    currentPage !== selectionLockedPageIndex;
                const shouldKeepStableSelection =
                    selectionLockedPageIndex !== null &&
                    lastStableSelectionPayload &&
                    (
                        lastInteractionState ||
                        didDetectHorizontalDrift ||
                        isRestoringSelectionPage
                    );

                // 在某些 WebKit 时序下（包括初始选区和段落跨页两种场景），
                // 原生选区可能短暂丢失，先尝试按最近一次 native offsets 恢复，
                // 避免退化成无系统拖拽手柄的状态。
                // iPhone 对跨列段落（首段接续上页）尤为敏感，此修复同时覆盖该场景。
                if (
                    shouldKeepStableSelection &&
                    !isRepairingContinuedNativeSelection &&
                    typeof continuedSelectionNativeStartOffset === 'number' &&
                    typeof continuedSelectionNativeEndOffset === 'number' &&
                    continuedSelectionNativeEndOffset > continuedSelectionNativeStartOffset
                ) {
                    isRepairingContinuedNativeSelection = true;
                    const keepHardLockAfterRepair =
                        isContinuingSelectionToNextPage ||
                        continuedSelectionAnchorOffset !== null ||
                        didDetectHorizontalDrift;
                    const shouldRestoreSoftLockAfterRepair =
                        !selectionHardLockEnabled && !keepHardLockAfterRepair;
                    const repairBeforeState = describeNativeSelectionState();
                    var repairSuccess = false;
                    setSelectionHardLock(true, 'repair');
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
                                repairSuccess = true;
                            }
                        }
                    } catch (e) {} finally {
                        if (shouldRestoreSoftLockAfterRepair) {
                            setSelectionHardLock(false, 'repair');
                        }
                        isRepairingContinuedNativeSelection = false;
                        postSelectionDebugLog(
                            'selection.restore.execute',
                            'source=repair' +
                            ',success=' + repairSuccess +
                            ',offsets=' + continuedSelectionNativeStartOffset + '-' + continuedSelectionNativeEndOffset +
                            ',before=' + repairBeforeState +
                            ',after=' + describeNativeSelectionState()
                        );
                    }
                }

                if (!payload && shouldKeepStableSelection) {
                    payload = cloneSelectionPayload(lastStableSelectionPayload);
                    payload.pageIndex = selectionLockedPageIndex;
                    payload.canContinueToNextPage = shouldOfferContinueSelectionToNextPage(payload);
                    updateSelectionVisualOverlay(payload);
                    postSelectionDebugLog(
                        'notifySelectionChange.overlayOnly',
                        'currentPage=' + currentPage +
                        ',lockedPage=' + selectionLockedPageIndex +
                        ',state=' + describeNativeSelectionState() +
                        ',payload=' + describeSelectionPayload(payload)
                    );
                } else if (!shouldKeepStableSelection) {
                    clearSelectionLockState();
                    hideSelectionVisualOverlay('notifySelectionChange.cleared', null);
                    payload = null;
                    postSelectionDebugLog(
                        'notifySelectionChange.cleared',
                        'page=' + currentPage + ',state=' + describeNativeSelectionState()
                    );
                }
            }
            try {
                if (payload) {
                    window.webkit.messageHandlers.textSelection.postMessage(payload);
                } else {
                    window.webkit.messageHandlers.textSelection.postMessage({
                        text: "",
                        cleanedText: "",
                        start: 0,
                        end: 0,
                        pageIndex: pageIndex,
                        rect: { x: 0, y: 0, width: 0, height: 0 },
                        canContinueToNextPage: false,
                        isSplitParagraphTailRegion: false
                    });
                }
            } catch (e) {}
        }

        // 文本选择处理
        document.addEventListener('selectionchange', notifySelectionChange);
        document.addEventListener('touchstart', function(event){
            notifyInteraction(true);
            if (event.touches && event.touches.length > 0) {
                touchPanStartX = event.touches[0].clientX;
                touchPanStartY = event.touches[0].clientY;
            }
        }, { passive: true });
        document.addEventListener('touchend', function(){ notifyInteraction(false); }, { passive: true });
        document.addEventListener('touchcancel', function(){ notifyInteraction(false); }, { passive: true });
        document.addEventListener('touchmove', function(event) {
            if (selectionLockedPageIndex === null || isContinuingSelectionToNextPage) { return; }
            if (event && event.touches && event.touches.length > 0) {
                var touch = event.touches[0];
                var dx = touch.clientX - touchPanStartX;
                var dy = touch.clientY - touchPanStartY;
                maybeLogReaderHorizontalDrag(dx, dy, 'selectionLocked', false);
            }
            enforceSelectionLockedPageIfNeeded();
        }, { passive: true });
        // Block native horizontal inertial scrolling in WebView.
        // Page turns are driven by Swift gesture + programmatic scrollToPage only.
        document.addEventListener('touchmove', function(event) {
            if (selectionLockedPageIndex !== null || isContinuingSelectionToNextPage) { return; }
            if (!event.touches || event.touches.length === 0) { return; }
            var touch = event.touches[0];
            var dx = touch.clientX - touchPanStartX;
            var dy = touch.clientY - touchPanStartY;
            if (Math.abs(dx) > Math.abs(dy) + 4) {
                event.preventDefault();
                maybeLogReaderHorizontalDrag(dx, dy, 'selectionUnlocked', true);
            }
        }, { passive: false });
        
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

        function isInjectedPageTopSpacerElement(element) {
            if (!element || element.nodeType !== Node.ELEMENT_NODE) { return false; }
            if (element.getAttribute('data-reader-page-top-spacer') === '1') { return true; }
            if (!element.classList) { return false; }
            return (
                element.classList.contains('reader-page-top-inline-spacer') ||
                element.classList.contains('reader-page-top-block-spacer')
            );
        }

        function isNodeInsideInjectedPageTopSpacer(node) {
            var current = node && node.nodeType === Node.ELEMENT_NODE ? node : (node ? node.parentElement : null);
            while (current) {
                if (isInjectedPageTopSpacerElement(current)) { return true; }
                current = current.parentElement;
            }
            return false;
        }

        function isIgnoredReaderNode(node) {
            if (!node) { return true; }
            if (isNodeInsideInjectedPageTopSpacer(node)) { return true; }

            var current = node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement;
            while (current) {
                var tag = current.tagName ? current.tagName.toUpperCase() : '';
                if (
                    tag === 'SCRIPT' ||
                    tag === 'STYLE' ||
                    tag === 'NOSCRIPT' ||
                    tag === 'TEMPLATE' ||
                    tag === 'META' ||
                    tag === 'LINK' ||
                    tag === 'TITLE'
                ) {
                    return true;
                }
                current = current.parentElement;
            }
            return false;
        }

        function resetGeneratedContinuations() {
            var list = document.querySelectorAll('.reader-generated-continuation');
            var nodes = [];
            for (var i = 0; i < list.length; i++) {
                nodes.push(list[i]);
            }
            for (var j = nodes.length - 1; j >= 0; j--) {
                var el = nodes[j];
                if (!el.parentNode) { continue; }
                var prev = el.previousElementSibling;
                if (!prev) {
                    el.parentNode.removeChild(el);
                    continue;
                }
                while (el.firstChild) {
                    prev.appendChild(el.firstChild);
                }
                el.parentNode.removeChild(el);
            }
        }

        function removeInjectedPageTopSpacers() {
            var injectedNodes = document.querySelectorAll('[data-reader-page-top-spacer="1"]');
            if (!injectedNodes || injectedNodes.length === 0) { return 0; }
            var parents = [];
            injectedNodes.forEach(function(node) {
                if (!node || !node.parentNode) { return; }
                parents.push(node.parentNode);
                node.parentNode.removeChild(node);
            });
            var normalizedParents = new Set();
            parents.forEach(function(parent) {
                if (!parent || typeof parent.normalize !== 'function') { return; }
                if (normalizedParents.has(parent)) { return; }
                parent.normalize();
                normalizedParents.add(parent);
            });
            return injectedNodes.length;
        }

        function getReaderBookRoot() {
            return document.querySelector('.reader-book-root') || document.body;
        }

        function isSplittableBlockElement(el) {
            if (!el || el.nodeType !== Node.ELEMENT_NODE) { return false; }
            if (isIgnoredReaderNode(el)) { return false; }
            if (isInjectedPageTopSpacerElement(el)) { return false; }
            return true;
        }

        function collectSplittableBlocks(root) {
            if (!root) { return []; }
            var all = Array.prototype.slice.call(root.querySelectorAll('p, li, blockquote, dd, dt'));
            var blocks = [];
            for (var i = 0; i < all.length; i++) {
                var el = all[i];
                if (!isSplittableBlockElement(el)) { continue; }
                var nested = false;
                for (var j = 0; j < all.length; j++) {
                    if (i === j) { continue; }
                    if (all[j].contains(el)) {
                        nested = true;
                        break;
                    }
                }
                if (nested) { continue; }
                blocks.push(el);
            }
            return blocks;
        }

        function getBlockTextRange(block, segments) {
            if (!block || !segments || segments.length === 0) { return null; }
            var minStart = null;
            var maxEnd = null;
            for (var i = 0; i < segments.length; i++) {
                var seg = segments[i];
                if (!seg || !seg.node) { continue; }
                try {
                    if (!block.contains(seg.node)) { continue; }
                } catch (e) {
                    continue;
                }
                if (minStart === null || seg.start < minStart) { minStart = seg.start; }
                if (maxEnd === null || seg.end > maxEnd) { maxEnd = seg.end; }
            }
            if (minStart === null || maxEnd === null) { return null; }
            return { start: minStart, endExclusive: maxEnd };
        }

        function charAtGlobalOffset(offset, segments) {
            var boundary = locateOffsetBoundary(offset, segments, true);
            if (!boundary || !boundary.node || boundary.node.nodeType !== Node.TEXT_NODE) { return ''; }
            var text = boundary.node.textContent || '';
            var idx = boundary.offset;
            if (idx < 0 || idx >= text.length) { return ''; }
            return text.charAt(idx);
        }

        function isLatinWordChar(ch) {
            return ch && /[A-Za-z0-9]/.test(ch);
        }

        function findFirstOffsetOnOrAfterPage(lo, hi, targetPage, segments) {
            var pHi = estimatePageIndexForOffset(hi, segments);
            if (pHi === null || pHi < targetPage) { return null; }
            var pLo = estimatePageIndexForOffset(lo, segments);
            if (pLo === null) { return null; }
            if (pLo >= targetPage) { return lo; }
            while (lo < hi) {
                var mid = Math.floor((lo + hi) / 2);
                var pm = estimatePageIndexForOffset(mid, segments);
                if (pm === null) { return null; }
                if (pm >= targetPage) {
                    hi = mid;
                } else {
                    lo = mid + 1;
                }
            }
            return lo;
        }

        function adjustSplitOffsetForWordBoundary(splitOffset, minOffset, segments) {
            var s = splitOffset;
            while (s > minOffset) {
                var cLeft = charAtGlobalOffset(s - 1, segments);
                var cHere = charAtGlobalOffset(s, segments);
                if (isLatinWordChar(cLeft) && isLatinWordChar(cHere)) {
                    s -= 1;
                } else {
                    break;
                }
            }
            return s;
        }

        function splitBlockAtDomOffset(block, splitOffset, segments) {
            var tr = getBlockTextRange(block, segments);
            if (!tr) { return false; }
            if (splitOffset <= tr.start || splitOffset >= tr.endExclusive) { return false; }

            var headProbe = extractTextFromOffsets(tr.start, splitOffset, segments);
            var tailProbe = extractTextFromOffsets(splitOffset, tr.endExclusive, segments);
            var stripWs = /\\s+/g;
            if (!headProbe || !headProbe.replace(stripWs, '')) { return false; }
            if (!tailProbe || !tailProbe.replace(stripWs, '')) { return false; }

            var boundary = locateOffsetBoundary(splitOffset, segments, true);
            if (!boundary || !boundary.node) { return false; }
            try {
                if (!block.contains(boundary.node)) { return false; }
            } catch (e) {
                return false;
            }

            var range = document.createRange();
            range.setStart(boundary.node, boundary.offset);
            range.setEnd(block, block.childNodes.length);
            var fragment = range.extractContents();
            range.detach();

            var tag = (block.tagName || 'p').toLowerCase();
            var cont = document.createElement(tag);
            cont.setAttribute('data-reader-generated-continuation', '1');
            cont.className = 'reader-generated-continuation';

            while (fragment.firstChild) {
                cont.appendChild(fragment.firstChild);
            }

            if (!block.parentNode) { return false; }
            block.parentNode.insertBefore(cont, block.nextSibling);
            return true;
        }

        function splitBlockElementIfCrossPage(block, segments) {
            var tr = getBlockTextRange(block, segments);
            if (!tr) { return false; }

            var firstNonWs = findNextNonWhitespaceOffset(tr.start, segments);
            if (firstNonWs === null || firstNonWs >= tr.endExclusive) { return false; }

            var startPage = estimatePageIndexForOffset(firstNonWs, segments);
            var lastChar = tr.endExclusive - 1;
            var endPage = estimatePageIndexForOffset(lastChar, segments);
            if (startPage === null || endPage === null) { return false; }
            if (startPage >= endPage) { return false; }

            var targetPage = startPage + 1;
            var splitOffset = findFirstOffsetOnOrAfterPage(firstNonWs, lastChar, targetPage, segments);
            if (splitOffset === null) { return false; }

            splitOffset = findNextNonWhitespaceOffset(splitOffset, segments);
            if (splitOffset === null || splitOffset >= tr.endExclusive) { return false; }
            if (splitOffset <= firstNonWs) { return false; }

            splitOffset = adjustSplitOffsetForWordBoundary(splitOffset, firstNonWs, segments);
            splitOffset = findNextNonWhitespaceOffset(splitOffset, segments);
            if (splitOffset === null || splitOffset >= tr.endExclusive) { return false; }
            if (splitOffset <= firstNonWs) { return false; }

            return splitBlockAtDomOffset(block, splitOffset, segments);
        }

        function splitCrossPageParagraphsIfNeeded() {
            var root = getReaderBookRoot();
            var segments = buildTextSegments();
            if (!segments || segments.length === 0) { return 0; }
            var blocks = collectSplittableBlocks(root);
            var splitCount = 0;
            for (var i = 0; i < blocks.length; i++) {
                if (splitBlockElementIfCrossPage(blocks[i], segments)) {
                    splitCount += 1;
                }
                segments = buildTextSegments();
            }
            return splitCount;
        }

        function computePageCount(shouldNotify) {
            const totalWidth = getTotalWidth();
            const perPage = getPerPage();
            const pages = Math.max(1, Math.ceil(totalWidth / perPage));
            if (shouldNotify !== false) {
                try { window.webkit.messageHandlers.pageMetrics.postMessage({ type: 'pageCount', value: pages }); } catch (e) {}
            }
            updateEdgeOverlay();
            return pages;
        }
        
        function applyPagination() {
            if (isApplyingPaginationLayout) {
                return computePageCount(true);
            }

            isApplyingPaginationLayout = true;
            const originalPerPage = getPerPage();
            const originalScrollLeft = getScrollLeft();
            const originalPageIndex = Math.max(
                0,
                Math.round(originalScrollLeft / Math.max(1, originalPerPage))
            );
            var finalPages = 1;

            try {
                // 始终禁用原生横向滚动，翻页只通过程序控制 scrollToPage。
                setHorizontalOverflowMode('hidden', 'applyPagination');

                removeInjectedPageTopSpacers();
                resetGeneratedContinuations();
                void document.body.offsetWidth;

                computePageCount(false);
                void document.body.offsetWidth;

                var maxSplitRounds = 3;
                for (var splitRound = 0; splitRound < maxSplitRounds; splitRound++) {
                    var splits = splitCrossPageParagraphsIfNeeded();
                    void document.body.offsetWidth;
                    computePageCount(false);
                    if (splits === 0) { break; }
                }

                finalPages = computePageCount(true);
            } catch (e) {
                finalPages = computePageCount(true);
            } finally {
                isApplyingPaginationLayout = false;
            }

            const clampedPageIndex = Math.max(0, Math.min(originalPageIndex, Math.max(0, finalPages - 1)));
            setScrollLeft(clampedPageIndex * getPerPage(), false, 'applyPagination.restorePage');
            updateEdgeOverlay();
            return finalPages;
        }
        
        function setScrollLeft(x, animated, sourceTag) {
            withSelectionHardLockTemporarilyDisabled(function() {
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
            }, sourceTag);
            // 更新右缘覆盖层显示状态
            if (animated) {
                setTimeout(updateEdgeOverlay, 360);
            } else {
                updateEdgeOverlay();
            }
        }

        function scrollToPage(index, animated, sourceTag) {
            const perPage = getPerPage();
            const x = Math.max(0, Math.floor(index) * perPage);
            setScrollLeft(x, animated, sourceTag);
        }
        
        window.addEventListener('load', function() {
            applyPagination();
            updateEdgeOverlay();
        });
        
        var selectionRectSyncScheduled = false;
        function syncSelectionRectAfterScrollIfNeeded() {
            if (isApplyingPaginationLayout) { return; }
            enforceSelectionLockedPageIfNeeded();
            if (selectionRectSyncScheduled) { return; }
            selectionRectSyncScheduled = true;
            requestAnimationFrame(function() {
                selectionRectSyncScheduled = false;
                enforceSelectionLockedPageIfNeeded();
                updateEdgeOverlay();
                try {
                    var current = Math.max(0, Math.round(getScrollLeft() / getPerPage()));
                    window.webkit.messageHandlers.pageMetrics.postMessage({ type: 'currentPage', value: current });
                } catch (e) {}
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
                clearSelectionLockState();
                hideSelectionVisualOverlay('applyHighlightForSelection', payload);
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

            const compact = findOffsetAfterCharacterCount(startOffset, 8, segments);
            if (compact !== null && compact > startOffset + 1) {
                return compact;
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
                postSelectionDebugLog(
                    'applySeedSelectionRange.nativeSuccess',
                    'start=' + startOffset + ',end=' + endOffset
                );
                return true;
            }

            // 退化路径：window.find 先找到文本后，再次尝试落回原生 Range。
            var seedText = extractTextFromOffsets(startOffset, endOffset, segments);
            if (!(seedText && seedText.trim().length > 0) || typeof window.find !== 'function') {
                postSelectionDebugLog(
                    'applySeedSelectionRange.invalidSeed',
                    'start=' + startOffset + ',end=' + endOffset + ',seedLen=' + (seedText ? seedText.length : 0)
                );
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
                found = !!withSelectionHardLockTemporarilyDisabled(function() {
                    var savedScroll = getScrollLeft();
                    var matched = !!window.find(seedText, true, false, false, false, false, false);
                    if (getScrollLeft() !== savedScroll) {
                        window.scrollTo(savedScroll, 0);
                    }
                    return matched;
                });
            } catch (e) {}

            if (!found) {
                postSelectionDebugLog(
                    'applySeedSelectionRange.findMiss',
                    'start=' + startOffset + ',end=' + endOffset + ',seedLen=' + seedText.length
                );
                return false;
            }
            var repaired = applyNativeSelectionRange(startOffset, endOffset, segments);
            postSelectionDebugLog(
                'applySeedSelectionRange.findHit',
                'start=' + startOffset +
                ',end=' + endOffset +
                ',seedLen=' + seedText.length +
                ',repaired=' + repaired +
                ',state=' + describeNativeSelectionState()
            );
            return repaired;
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

        function clearNativeSelectionOnly() {
            try {
                var selection = window.getSelection ? window.getSelection() : null;
                if (selection && selection.removeAllRanges) {
                    selection.removeAllRanges();
                }
            } catch (e) {}
            postSelectionDebugLog('clearNativeSelectionOnly', describeNativeSelectionState());
        }

        function extendCurrentNativeSelection(endOffset, segments) {
            const resolvedSegments = segments || buildTextSegments();
            const endBoundary = locateOffsetBoundary(endOffset, resolvedSegments, false);
            const selection = window.getSelection ? window.getSelection() : null;
            if (!selection || !endBoundary || !endBoundary.node) {
                postSelectionDebugLog(
                    'extendCurrentNativeSelection.invalidTarget',
                    'end=' + endOffset + ',state=' + describeNativeSelectionState()
                );
                return false;
            }

            const existingText = selection.toString ? selection.toString() : '';
            if (!(selection.rangeCount > 0 && existingText && existingText.trim().length > 0)) {
                postSelectionDebugLog(
                    'extendCurrentNativeSelection.noActiveSelection',
                    'end=' + endOffset + ',state=' + describeNativeSelectionState()
                );
                return false;
            }

            focusReaderDocument();

            var applied = false;
            if (typeof selection.extend === 'function') {
                try {
                    selection.extend(endBoundary.node, endBoundary.offset);
                    applied = selection.rangeCount > 0 && !!selection.toString();
                } catch (e) {}
            }

            if (!applied &&
                typeof selection.setBaseAndExtent === 'function' &&
                selection.anchorNode) {
                try {
                    selection.setBaseAndExtent(
                        selection.anchorNode,
                        selection.anchorOffset,
                        endBoundary.node,
                        endBoundary.offset
                    );
                    applied = selection.rangeCount > 0 && !!selection.toString();
                } catch (e) {}
            }

            postSelectionDebugLog(
                'extendCurrentNativeSelection',
                'end=' + endOffset +
                ',applied=' + applied +
                ',state=' + describeNativeSelectionState()
            );
            return applied;
        }

        function finishPendingContinuationSelection(request, selectionSegments) {
            var updatedNative = serializeSelection();
            if (!selectionHasText(updatedNative)) {
                postSelectionDebugLog(
                    'finishPendingContinuationSelection.empty',
                    'requestPage=' + request.nextPage + ',state=' + describeNativeSelectionState()
                );
                return false;
            }

            continuedSelectionAnchorOffset = request.anchorStart;
            selectionLockedPageIndex = request.nextPage;
            setSelectionHardLock(true, 'continueSelectionToNextPage');

            var updated = buildEffectiveSelectionPayload(updatedNative, selectionSegments);
            updated.pageIndex = request.nextPage;
            updated.canContinueToNextPage = shouldOfferContinueSelectionToNextPage(updated);
            continuedSelectionNativeStartOffset = updatedNative.start;
            continuedSelectionNativeEndOffset = updatedNative.end;
            lastStableSelectionPayload = cloneSelectionPayload(updated);
            updateSelectionVisualOverlay(updated);

            pendingContinuationSelection = null;
            isContinuingSelectionToNextPage = false;
            postSelectionDebugLog(
                'finishPendingContinuationSelection.success',
                describeSelectionPayload(updated)
            );
            try { window.webkit.messageHandlers.textSelection.postMessage(updated); } catch (e) {}
            setTimeout(function() {
                notifySelectionChange();
            }, 50);
            return true;
        }

        function performPendingContinuationSelection(attempt) {
            if (!pendingContinuationSelection) { return; }
            var request = pendingContinuationSelection;
            var currentAttempt = Math.max(0, Math.floor(attempt || 0));
            postSelectionDebugLog(
                'performPendingContinuationSelection.begin',
                'attempt=' + currentAttempt +
                ',nextPage=' + request.nextPage +
                ',nextStart=' + request.nextStartOffset +
                ',state=' + describeNativeSelectionState()
            );

            requestAnimationFrame(function() {
                requestAnimationFrame(function() {
                    if (pendingContinuationSelection !== request) { return; }
                    try {
                        focusReaderDocument();
                        var selectionSegments = buildTextSegments();
                        if (!selectionSegments || selectionSegments.length === 0) {
                            selectionSegments = request.segments || [];
                        }

                        var targetEndOffset = resolveSeedSelectionEndOffset(request.nextStartOffset, selectionSegments);
                        if (!(targetEndOffset > request.nextStartOffset)) {
                            targetEndOffset = request.nextStartOffset + 1;
                        }
                        postSelectionDebugLog(
                            'performPendingContinuationSelection.target',
                            'attempt=' + currentAttempt +
                            ',nextStart=' + request.nextStartOffset +
                            ',targetEnd=' + targetEndOffset +
                            ',segments=' + selectionSegments.length
                        );

                        if (
                            (
                                extendCurrentNativeSelection(targetEndOffset, selectionSegments) ||
                                applySeedSelectionRange(request.nextStartOffset, targetEndOffset, selectionSegments)
                            ) &&
                            finishPendingContinuationSelection(request, selectionSegments)
                        ) {
                            return;
                        }
                    } catch (e) {}

                    if (pendingContinuationSelection !== request) { return; }
                    if (currentAttempt < 2) {
                        setTimeout(function() {
                            performPendingContinuationSelection(currentAttempt + 1);
                        }, 30);
                        return;
                    }

                    pendingContinuationSelection = null;
                    isContinuingSelectionToNextPage = false;
                    clearSelectionLockState();
                    hideSelectionVisualOverlay('performPendingContinuationSelection.failed', null);
                    postSelectionDebugLog(
                        'performPendingContinuationSelection.failed',
                        'attempt=' + currentAttempt + ',state=' + describeNativeSelectionState()
                    );
                    notifySelectionChange();
                });
            });
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
                postSelectionDebugLog(
                    'continueSelectionToNextPage.begin',
                    'native=' + describeSelectionPayload(nativePayload) +
                    ',effective=' + describeSelectionPayload(payload)
                );

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
                continuedSelectionNativeStartOffset = nativePayload.start;
                continuedSelectionNativeEndOffset = nativePayload.end;
                pendingContinuationSelection = {
                    anchorStart: payload.start,
                    nextStartOffset: nextStartOffset,
                    nextPage: nextPage,
                    segments: segments
                };
                postSelectionDebugLog(
                    'continueSelectionToNextPage.scheduled',
                    'anchorStart=' + payload.start +
                    ',nextStart=' + nextStartOffset +
                    ',nextPage=' + nextPage +
                    ',currentPage=' + currentPage
                );

                selectionLockedPageIndex = nextPage;
                setSelectionHardLock(true, 'continueSelectionToNextPage');
                isRestoringSelectionPage = true;
                scrollToPage(nextPage, false, 'continueSelectionToNextPage');
                isRestoringSelectionPage = false;

                rafScheduled = true;
                performPendingContinuationSelection(0);
                return { success: true, pageIndex: nextPage };
            } finally {
                if (!rafScheduled) {
                    pendingContinuationSelection = null;
                    isContinuingSelectionToNextPage = false;
                    postSelectionDebugLog('continueSelectionToNextPage.finallyNoSchedule', describeNativeSelectionState());
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

        var contentLinkTapBound = false;
        function bindContentLinkTapHandler() {
            if (contentLinkTapBound) { return; }

            function hasAncestorWithClass(node, className) {
                var current = node;
                while (current) {
                    if (current.classList && current.classList.contains(className)) {
                        return true;
                    }
                    current = current.parentElement;
                }
                return false;
            }

            function findNearestLink(node) {
                var current = node;
                while (current) {
                    if (current.tagName && String(current.tagName).toLowerCase() === 'a') {
                        return current;
                    }
                    current = current.parentElement;
                }
                return null;
            }

            function hasTOCHint(node) {
                var current = node;
                while (current) {
                    if (current.tagName && String(current.tagName).toLowerCase() === 'nav') {
                        return true;
                    }
                    var roleAttr = '';
                    var typeAttr = '';
                    try {
                        roleAttr = (current.getAttribute && current.getAttribute('role')) || '';
                        typeAttr = (current.getAttribute && (current.getAttribute('epub:type') || current.getAttribute('type'))) || '';
                    } catch (e) {}
                    var normalizedRole = String(roleAttr).toLowerCase();
                    var normalizedType = String(typeAttr).toLowerCase();
                    if (normalizedRole.indexOf('doc-toc') >= 0 ||
                        normalizedRole.indexOf('toc') >= 0 ||
                        normalizedType.indexOf('toc') >= 0) {
                        return true;
                    }
                    current = current.parentElement;
                }
                return false;
            }

            function hasFootnoteHint(linkNode) {
                if (!linkNode) { return false; }
                var attrs = '';
                try {
                    attrs = [
                        linkNode.getAttribute('epub:type') || '',
                        linkNode.getAttribute('type') || '',
                        linkNode.getAttribute('role') || '',
                        linkNode.getAttribute('rel') || '',
                        linkNode.className || ''
                    ].join(' ').toLowerCase();
                } catch (e) {
                    attrs = '';
                }
                if (attrs.indexOf('noteref') >= 0 ||
                    attrs.indexOf('footnote') >= 0 ||
                    attrs.indexOf('doc-noteref') >= 0) {
                    return true;
                }

                var href = '';
                try { href = (linkNode.getAttribute('href') || '').toLowerCase(); } catch (e) {}
                if (href.indexOf('footnote') >= 0 || href.indexOf('fn') >= 0 || href.indexOf('note') >= 0) {
                    return true;
                }
                return false;
            }

            document.addEventListener('click', function(event) {
                var target = event ? event.target : null;
                if (!target) { return; }
                if (hasAncestorWithClass(target, 'reader-highlight')) { return; }

                var linkNode = findNearestLink(target);
                if (!linkNode) { return; }

                var rawHref = '';
                try { rawHref = (linkNode.getAttribute('href') || '').trim(); } catch (e) {}
                if (!rawHref) { return; }

                var normalizedHref = rawHref.toLowerCase();
                if (normalizedHref.startsWith('javascript:')) { return; }

                var isExternal = /^(https?:|mailto:|tel:|sms:)/i.test(rawHref);
                var text = '';
                try { text = (linkNode.textContent || '').trim(); } catch (e) { text = ''; }
                var tocHint = hasTOCHint(linkNode);
                var footnoteHint = hasFootnoteHint(linkNode);

                try {
                    window.webkit.messageHandlers.contentLinkTap.postMessage({
                        href: rawHref,
                        text: text,
                        isExternal: !!isExternal,
                        isFootnoteHint: !!footnoteHint,
                        isTOCHint: !!tocHint
                    });
                } catch (e) {}

                if (event && event.preventDefault) { event.preventDefault(); }
                if (event && event.stopPropagation) { event.stopPropagation(); }
            }, true);

            contentLinkTapBound = true;
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

        bindContentLinkTapHandler();
        bindHighlightTapHandler();
        """
    }
}
