//
//  ReaderView.swift
//  LanRead
//
//  Created by 郭亮 on 2025/9/10.
//

import SwiftUI
import CoreData
import UIKit

struct ReaderView: View {
    let book: Book
    private let initialLocation: BookmarkLocation?
    
    @FetchRequest private var bookmarks: FetchedResults<Bookmark>
    @StateObject private var appSettings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var systemColorScheme
    
    @FetchRequest private var highlights: FetchedResults<Highlight>
    init(book: Book, initialLocation: BookmarkLocation? = nil) {
        self.book = book
        self.initialLocation = initialLocation
        _bookmarks = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Bookmark.createdAt, ascending: false)],
            predicate: NSPredicate(format: "book == %@", book)
        )
        _highlights = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Highlight.createdAt, ascending: false)],
            predicate: NSPredicate(format: "book == %@", book)
        )
    }
    
    @State private var chapters: [Chapter] = []
    @State private var tocItems: [TOCItem] = []
    @State private var currentChapterIndex = 0
    @State private var isLoading = true
    @State private var loadError: String?
    
    @State private var showingToolbar = false
    @State private var showingTableOfContents = false
    @State private var showingSettings = false
    @State private var selectedTextInfo: SelectedTextInfo?
    @State private var selectionAction: ReaderSelectionAction?
    @State private var isInteractingWithWebContent = false
    @State private var showingNoteEditor = false
    @State private var noteDraft = ""
    @State private var showingAIResponse = false
    @State private var aiResponseTitle = ""
    @State private var aiResponseContent = ""
    @State private var aiActionInFlight: AIAction?
    @State private var aiInsertionTarget: AIInsertionTarget?
    @State private var isLoadingAIResponse = false
    @State private var aiErrorMessage: String?
    @State private var activeHighlight: Highlight?
    @State private var activeHighlightText: String = ""
    @State private var showingHighlightActions = false
    @State private var pendingDeleteHighlight: Highlight?
    @State private var deletingNoteOnly = false
    @State private var showingDeleteConfirmation = false
    @State private var hintMessage: String?
    @State private var showingAISummary = false
    @State private var isFirstOpen = true
    @State private var didApplyInitialLocation = false
    
    @State private var scrollOffset: CGFloat = 0
    @State private var lastTapTime: Date = Date()
    
    // 新增滑动翻页相关状态
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var dragStartLocation: CGPoint = .zero
    @State private var isAnimatingPageTurn: Bool = false
    @State private var pendingTapWorkItem: DispatchWorkItem?
    @State private var lastNavigationTapTime: Date?
    @State private var lastWebContentTapTime: Date?
    private let swipePagingEnabled = true
    private let tapNavigationEdgeRatio: CGFloat = 0.24
    @State private var pageTurnAnimationStyle: PageTurnAnimationStyle = .fade
    
    private var effectiveColorScheme: ColorScheme {
        appSettings.theme.colorScheme ?? systemColorScheme
    }

    private enum AIAction {
        case translate
        case explain
    }

    private enum AIInsertionTarget {
        case selection
        case highlight(Highlight)
    }
    
    // Pagination states per chapter
    @State private var chapterPageIndices: [Int] = []
    @State private var chapterTotalPages: [Int] = []
    
    // Reading time tracking
    @State private var readingStartTime: Date?
    @State private var isActivelyReading: Bool = false
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        ZStack {
            // Premium background with subtle gradient
            backgroundView
                .ignoresSafeArea()
            
            if isLoading {
                loadingView
            } else if let error = loadError {
                errorView(error)
            } else {
                mainContentView
            }
        }
        .navigationBarHidden(true)
        .preferredColorScheme(appSettings.theme.colorScheme)
        .statusBar(hidden: !showingToolbar)
        .sheet(isPresented: $showingTableOfContents) {
            TableOfContentsView(tocItems: tocItems, chapters: chapters, currentChapterIndex: $currentChapterIndex)
        }
        .sheet(isPresented: $showingSettings) {
            ReaderSettingsView()
        }
        .sheet(isPresented: $showingNoteEditor) {
            noteEditorSheet
        }
        .sheet(isPresented: $showingAIResponse) {
            aiResponseSheet
        }
        .sheet(isPresented: $showingHighlightActions) {
            highlightActionSheet
        }
        .overlay(alignment: .top) {
            if let hintMessage {
                hintBanner(hintMessage)
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            loadBookContent()
            checkFirstTimeOpen()
            startReadingSession()
        }
        .onDisappear {
            // Save reading progress when view disappears (e.g., user navigates back)
            saveReadingProgress()
            endReadingSession()
            pendingTapWorkItem?.cancel()
        }
        .onChange(of: scenePhase) { newPhase in
            handleScenePhaseChange(newPhase)
        }
        .onChange(of: currentChapterIndex) { _ in
            // Save progress when chapter changes
            saveReadingProgress()
            selectedTextInfo = nil
        }
        .confirmationDialog(
            deletingNoteOnly ? NSLocalizedString("highlight.action.delete_note_confirm", comment: "") : NSLocalizedString("highlight.action.delete_highlight_confirm", comment: ""),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                deletingNoteOnly ? NSLocalizedString("highlight.action.delete_note", comment: "") : NSLocalizedString("highlight.action.delete_highlight", comment: ""),
                role: .destructive
            ) {
                handleHighlightDeletion()
            }
            Button(NSLocalizedString("取消", comment: ""), role: .cancel) {
                pendingDeleteHighlight = nil
                deletingNoteOnly = false
            }
        }
    }
    
    // MARK: - View Components
    
    private var backgroundView: some View {
        Group {
            if effectiveColorScheme == .dark {
                // Deep, rich dark theme with subtle gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.08),
                        Color(red: 0.02, green: 0.02, blue: 0.05)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                // Clean, paper-like light theme with warmth
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.98, green: 0.98, blue: 0.99),
                        Color(red: 0.96, green: 0.96, blue: 0.97)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.primary.opacity(0.6))
            
            Text(NSLocalizedString("正在加载书籍...", comment: ""))
                .font(.system(.body, design: .rounded))
                .foregroundColor(.secondary)
        }
    }
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text(NSLocalizedString("加载失败", comment: ""))
                .font(.system(.title2, design: .rounded))
                .fontWeight(.semibold)
            
            Text(error)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(action: { dismiss() }) {
                Text(NSLocalizedString("返回", comment: ""))
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(12)
            }
        }
    }
    
    private var mainContentView: some View {
        ZStack {
            // Reading content
            GeometryReader { geometry in
                if !chapters.isEmpty && currentChapterIndex >= 0 && currentChapterIndex < chapters.count {
                    chapterView(index: currentChapterIndex, chapter: chapters[currentChapterIndex], geometry: geometry)
                        .id(currentChapterIndex)
                }
            }
            
            // Elegant toolbar overlay
            VStack(spacing: 0) {
                if showingToolbar {
                    topToolbar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                Spacer()
                
                if showingToolbar {
                    bottomToolbar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: showingToolbar)
        }
    }
    
    private func chapterView(index: Int, chapter: Chapter, geometry: GeometryProxy) -> some View {
        ZStack {
            // Content WebView with horizontal pagination
            // 为页码显示预留空间：页码高度约50px（包括padding和背景）
            let pageIndicatorHeight: CGFloat = 50
            let webViewHeight = geometry.size.height - pageIndicatorHeight
            
            ReaderWebView(
                htmlContent: chapter.htmlContent,
                appSettings: appSettings,
                isDarkMode: effectiveColorScheme == .dark,
                currentPageIndex: Binding(
                    get: { safeChapterPageIndex(index) },
                    set: { newValue in setChapterPageIndex(index, newValue) }
                ),
                totalPages: Binding(
                    get: { safeChapterTotalPages(index) },
                    set: { newValue in setChapterTotalPages(index, newValue) }
                ),
                selectionAction: $selectionAction,
                highlights: highlightsForChapter(index),
                pageTurnStyle: pageTurnAnimationStyle,
                onToolbarToggle: {
                    handleTap()
                },
                onTextSelection: { info in
                    let trimmed = info.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        selectedTextInfo = nil
                    } else {
                        pendingTapWorkItem?.cancel()
                        let updatedInfo = SelectedTextInfo(
                            text: trimmed,
                            startOffset: info.startOffset,
                            endOffset: info.endOffset,
                            rect: info.rect,
                            pageIndex: info.pageIndex
                        )
                        selectedTextInfo = updatedInfo
                        let feedback = UISelectionFeedbackGenerator()
                        feedback.selectionChanged()
                    }
                },
                onHighlightTap: { info in
                    handleHighlightTap(info)
                },
                onLoadFinished: nil,
                onInteractionChange: { isActive in
                    isInteractingWithWebContent = isActive
                }
            )
            .frame(width: geometry.size.width, height: webViewHeight)
            .offset(x: dragOffset)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        guard selectedTextInfo == nil else { return }
                        handleDragChanged(value, geometry: geometry)
                    }
                    .onEnded { value in
                        if isDragging {
                            handleDragEnded(value, geometry: geometry)
                        } else if selectedTextInfo == nil {
                            handleNavigationTap(at: value.startLocation, geometry: geometry)
                        }
                        isDragging = false
                    }
            )
            .onChange(of: appSettings.pageMargins) { _ in
                // 版心变化后，保持页码在合法范围
                clampCurrentPage(index)
            }
            .onChange(of: appSettings.readingFontSize) { _ in
                clampCurrentPage(index)
            }
            .onChange(of: appSettings.lineSpacing) { _ in
                clampCurrentPage(index)
            }
            
            // AI Summary overlay for first chapter on first open
            if showingAISummary && isFirstOpen && chapter.order == 0 {
                VStack {
                    AISummaryCard(book: book)
                        .padding(.horizontal, horizontalPadding(for: geometry))
                        .padding(.top, 60)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    Spacer()
                }
            }
            // 滑动视觉反馈
            if isDragging {
                slideVisualFeedback(geometry: geometry)
            }
            
            // Page indicator (在预留的空间中显示)
            if safeChapterTotalPages(index) > 1 {
                VStack {
                    Spacer()
                        .frame(height: webViewHeight) // 占据WebView的高度
                    
                    // 页码显示在预留的空间中
                    HStack {
                        Spacer()
                        Text("\(safeChapterPageIndex(index) + 1) / \(safeChapterTotalPages(index))")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                        Spacer()
                    }
                    .frame(height: pageIndicatorHeight) // 使用预留的高度
                }
                .transition(.opacity)
            }

            if let info = selectedTextInfo {
                selectionToolbar(for: info, in: geometry)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
    
    private func horizontalPadding(for geometry: GeometryProxy) -> CGFloat {
        let width = geometry.size.width
        // Adaptive padding based on screen size for optimal reading width
        if width > 1000 {
            return width * 0.20 // Large iPad
        } else if width > 700 {
            return width * 0.15 // iPad
        } else {
            return max(appSettings.pageMargins, 24) // iPhone
        }
    }
    
    private var topToolbar: some View {
        HStack(spacing: 16) {
            // Back button
            Button(action: { 
                // Save reading progress before dismissing
                saveReadingProgress()
                dismiss() 
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(0.08))
                            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                    )
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(book.displayTitle)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                
                if !chapters.isEmpty {
                    Text(chapters[currentChapterIndex].title)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Table of contents
            Button(action: { showingTableOfContents = true }) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(0.08))
                            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                    )
            }
            
            // Settings
            Button(action: { showingSettings = true }) {
                Image(systemName: "textformat.size")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(0.08))
                            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 0)
        )
    }
    
    private var bottomToolbar: some View {
        VStack(spacing: 16) {
            // Chapter progress indicator
            if chapters.count > 1 {
                HStack(spacing: 8) {
                    Text("\(currentChapterIndex + 1)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .frame(minWidth: 30)
                    
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Track
                            Capsule()
                                .fill(Color.primary.opacity(0.1))
                                .frame(height: 4)
                            
                            // Progress
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.blue, .blue.opacity(0.8)]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * CGFloat(currentChapterIndex + 1) / CGFloat(chapters.count), height: 4)
                        }
                    }
                    .frame(height: 4)
                    
                    Text("\(chapters.count)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .frame(minWidth: 30)
                }
                .padding(.horizontal, 20)
            }
            
            // Action buttons
            HStack(spacing: 0) {
                toolbarButton(icon: currentBookmark == nil ? "bookmark" : "bookmark.fill", action: { toggleBookmark() }, isActive: currentBookmark != nil)
                toolbarButton(icon: "highlighter", action: { handleQuickHighlight() })
                toolbarButton(icon: "square.and.arrow.up", action: {})
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 16)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 0)
        )
    }
    
    private func toolbarButton(icon: String, action: @escaping () -> Void, isActive: Bool = false) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(isActive ? .blue : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isActive ? Color.blue.opacity(0.12) : Color.clear)
                )
        }
    }

    // MARK: - Selection & Notes

    private func selectionToolbar(for info: SelectedTextInfo, in geometry: GeometryProxy) -> some View {
        let safeTop = geometry.safeAreaInsets.top + 12
        let fallbackRect = CGRect(x: geometry.size.width / 2, y: geometry.size.height * 0.25, width: 0, height: 0)
        let rect = info.rect == .zero ? fallbackRect : info.rect
        let toolbarHeight: CGFloat = 64
        let horizontalPadding = min(120, geometry.size.width / 2)
        let clampedX = min(max(rect.midX, horizontalPadding), geometry.size.width - horizontalPadding)
        let preferredY = rect.minY - toolbarHeight / 2
        let clampedY = min(max(preferredY, safeTop), geometry.size.height - toolbarHeight - 16)

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                selectionActionButton(
                    title: NSLocalizedString("高亮标记", comment: ""),
                    systemImage: "highlighter",
                    tint: .yellow.opacity(0.9),
                    action: { commitHighlight(note: nil) }
                )

                selectionActionButton(
                    title: NSLocalizedString("添加笔记", comment: ""),
                    systemImage: "note.text",
                    tint: .blue.opacity(0.9),
                    action: { prepareNoteEditor() }
                )

                selectionActionButton(
                    title: NSLocalizedString("复制", comment: ""),
                    systemImage: "doc.on.doc",
                    tint: .secondary,
                    action: { handleCopySelectedText() }
                )

                selectionActionButton(
                    title: NSLocalizedString("翻译", comment: ""),
                    systemImage: "globe",
                    tint: .green,
                    action: { startAIRequest(.translate) }
                )

                selectionActionButton(
                    title: NSLocalizedString("AI 解释", comment: ""),
                    systemImage: "brain.head.profile",
                    tint: .purple,
                    action: { startAIRequest(.explain) }
                )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: min(geometry.size.width - 32, geometry.size.width))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 8)
        .position(x: clampedX, y: clampedY)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: selectedTextInfo)
    }

    private func selectionActionButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(tint)
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }

    private func handleHighlightTap(_ info: HighlightTapInfo) {
        suppressNavigationForWebContentTap()
        guard let target = highlights.first(where: { $0.id == info.id }) else {
            DebugLogger.error("ReaderView: 未找到点击的高亮，id=\(info.id)")
            return
        }
        activeHighlight = target
        let tappedText = info.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedText = target.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        activeHighlightText = tappedText.isEmpty ? storedText : tappedText
        showingHighlightActions = true
        selectedTextInfo = nil
    }

    private func prepareNoteEditor() {
        guard selectedTextInfo != nil else {
            showHint(NSLocalizedString("请先长按选择文字", comment: ""))
            return
        }
        noteDraft = ""
        showingNoteEditor = true
    }

    private func handleQuickHighlight() {
        guard selectedTextInfo != nil else {
            showHint(NSLocalizedString("长按文字后再高亮", comment: ""))
            return
        }
        commitHighlight(note: nil)
    }

    private func handleCopySelectedText() {
        guard let info = selectedTextInfo else {
            showHint(NSLocalizedString("请选择要复制的内容", comment: ""))
            return
        }
        UIPasteboard.general.string = info.text
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.success)
        showHint(NSLocalizedString("已复制到剪贴板", comment: ""))
    }

    private func startAIRequest(_ action: AIAction, sourceText: String? = nil, targetHighlight: Highlight? = nil) {
        var resolvedText = sourceText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if resolvedText.isEmpty, let info = selectedTextInfo?.text.trimmingCharacters(in: .whitespacesAndNewlines), !info.isEmpty {
            resolvedText = info
        }
        if resolvedText.isEmpty, let highlight = targetHighlight?.selectedText.trimmingCharacters(in: .whitespacesAndNewlines), !highlight.isEmpty {
            resolvedText = highlight
        }

        guard !resolvedText.isEmpty else {
            showHint(NSLocalizedString("请选择文字后使用 AI", comment: ""))
            return
        }
        guard !isLoadingAIResponse else { return }

        aiActionInFlight = action
        aiInsertionTarget = targetHighlight != nil ? .highlight(targetHighlight!) : (selectedTextInfo != nil ? .selection : nil)
        aiResponseTitle = action == .translate ? NSLocalizedString("翻译", comment: "") : NSLocalizedString("AI 解释", comment: "")
        aiResponseContent = ""
        aiErrorMessage = nil
        showingAIResponse = true
        isLoadingAIResponse = true

        let text = resolvedText
        Task {
            do {
                let result: String
                switch action {
                case .translate:
                    result = try await ReadingAIService.shared.translate(text: text, targetLanguage: appSettings.translationLanguage)
                case .explain:
                    result = try await ReadingAIService.shared.explain(text: text, locale: appSettings.language)
                }

                await MainActor.run {
                    aiResponseContent = result.trimmingCharacters(in: .whitespacesAndNewlines)
                    isLoadingAIResponse = false
                }
            } catch {
                DebugLogger.error("ReaderView: AI 请求失败", error: error)
                await MainActor.run {
                    aiErrorMessage = error.localizedDescription
                    isLoadingAIResponse = false
                }
            }
        }
    }

    private var canInsertAIContent: Bool {
        guard aiErrorMessage == nil else { return false }
        guard !isLoadingAIResponse else { return false }
        return aiInsertionTarget != nil && !aiResponseContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func insertAIContentIntoNote() {
        let content = aiResponseContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        guard let target = aiInsertionTarget else { return }

        switch target {
        case .highlight(let highlight):
            let existing = highlight.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if existing.isEmpty {
                highlight.note = content
            } else {
                highlight.note = existing + "\n\n" + content
            }
            highlight.updatedAt = Date()

            do {
                try viewContext.save()
                showHint(NSLocalizedString("highlight.action.insert_success", comment: ""))
            } catch {
                DebugLogger.error("ReaderView: 保存AI笔记失败", error: error)
                showHint(NSLocalizedString("保存高亮失败", comment: ""))
            }
        case .selection:
            commitHighlight(note: content)
        }

        aiInsertionTarget = nil
        showingAIResponse = false
        aiActionInFlight = nil
    }

    private func showHint(_ message: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            hintMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeInOut(duration: 0.2)) {
                hintMessage = nil
            }
        }
    }

    private func commitHighlight(note: String?) {
        guard let info = selectedTextInfo else {
            showHint(NSLocalizedString("请先长按选择文字", comment: ""))
            return
        }

        let trimmed = info.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let start = min(info.startOffset, info.endOffset)
        let end = max(info.startOffset, info.endOffset)
        guard start < end else { return }

        guard let startPosition = encodeAnchor(
            chapterIndex: currentChapterIndex,
            pageIndex: info.pageIndex,
            offset: start
        ), let endPosition = encodeAnchor(
            chapterIndex: currentChapterIndex,
            pageIndex: info.pageIndex,
            offset: end
        ) else {
            showHint(NSLocalizedString("标记失败，请重试", comment: ""))
            return
        }

        let highlight = Highlight(context: viewContext)
        highlight.id = UUID()
        highlight.selectedText = trimmed
        highlight.startPosition = startPosition
        highlight.endPosition = endPosition
        if currentChapterIndex < chapters.count {
            highlight.chapter = chapters[currentChapterIndex].title
        }
        highlight.pageNumber = Int32(max(0, info.pageIndex))
        let colorHex = Color.yellow.hexString
        highlight.colorHex = colorHex
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedNote.isEmpty {
            highlight.note = trimmedNote
        }
        highlight.createdAt = Date()
        highlight.updatedAt = Date()
        highlight.book = book

        do {
            try viewContext.save()
            selectionAction = ReaderSelectionAction(type: .highlight(colorHex: colorHex))
            let feedback = UINotificationFeedbackGenerator()
            feedback.notificationOccurred(.success)
            showHint(trimmedNote.isEmpty ? NSLocalizedString("已高亮所选内容", comment: "") : NSLocalizedString("已添加带笔记的高亮", comment: ""))
            selectedTextInfo = nil
        } catch {
            DebugLogger.error("ReaderView: 保存高亮失败", error: error)
            showHint(NSLocalizedString("保存高亮失败", comment: ""))
        }
    }

    private func highlightsForChapter(_ chapterIndex: Int) -> [ReaderHighlight] {
        highlights.compactMap { highlight in
            guard let start = decodeAnchor(from: highlight.startPosition),
                  let end = decodeAnchor(from: highlight.endPosition),
                  start.chapterIndex == chapterIndex,
                  end.chapterIndex == chapterIndex else {
                return nil
            }

            return ReaderHighlight(
                id: highlight.id,
                startOffset: start.offset,
                endOffset: end.offset,
                colorHex: highlight.colorHex
            )
        }
    }

    private func encodeAnchor(chapterIndex: Int, pageIndex: Int, offset: Int) -> String? {
        let anchor = SelectionAnchor(chapterIndex: chapterIndex, pageIndex: pageIndex, offset: offset)
        guard let data = try? JSONEncoder().encode(anchor) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func decodeAnchor(from string: String?) -> SelectionAnchor? {
        guard let string,
              let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SelectionAnchor.self, from: data)
    }

    private var noteEditorSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if let text = selectedTextInfo?.text {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(NSLocalizedString("选中文本", comment: ""))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Text(text)
                            .font(.system(size: 15, design: .serif))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(10)
                    }
                }

                TextEditor(text: $noteDraft)
                    .frame(minHeight: 180)
                    .padding(8)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.08))
                    )

                Spacer()
            }
            .padding()
            .navigationTitle(NSLocalizedString("添加笔记", comment: ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("取消", comment: "")) {
                        showingNoteEditor = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("保存", comment: "")) {
                        commitHighlight(note: noteDraft)
                        showingNoteEditor = false
                    }
                    .disabled(noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var highlightActionSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if let highlight = activeHighlight {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("highlight.action.content", comment: ""))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Text(activeHighlightText.isEmpty ? highlight.selectedText : activeHighlightText)
                            .font(.system(size: 16, design: .serif))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(12)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("highlight.action.note", comment: ""))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        if let note = highlight.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                            ScrollView {
                                Text(note)
                                    .font(.system(size: 15, design: .serif))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                            }
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(12)
                        } else {
                            Text(NSLocalizedString("highlight.action.no_note", comment: ""))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color.primary.opacity(0.04))
                                .cornerRadius(12)
                        }
                    }

                    VStack(spacing: 12) {
                        Button {
                            showingHighlightActions = false
                            startAIRequest(.translate, sourceText: highlight.selectedText, targetHighlight: highlight)
                        } label: {
                            Label(NSLocalizedString("翻译", comment: ""), systemImage: "globe")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            showingHighlightActions = false
                            startAIRequest(.explain, sourceText: highlight.selectedText, targetHighlight: highlight)
                        } label: {
                            Label(NSLocalizedString("AI 解释", comment: ""), systemImage: "brain.head.profile")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        if let note = highlight.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                            Button(role: .destructive) {
                                requestHighlightDeletion(highlight, noteOnly: true)
                            } label: {
                                Label(NSLocalizedString("highlight.action.delete_note", comment: ""), systemImage: "trash")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }

                        Button(role: .destructive) {
                            requestHighlightDeletion(highlight, noteOnly: false)
                        } label: {
                            Label(NSLocalizedString("highlight.action.delete_highlight", comment: ""), systemImage: "trash.slash")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Text(NSLocalizedString("暂无内容", comment: ""))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                }

                Spacer()
                adBannerSection
            }
            .padding()
            .navigationTitle(NSLocalizedString("highlight.action.title", comment: ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("关闭", comment: "")) {
                        showingHighlightActions = false
                        activeHighlight = nil
                    }
                }
            }
        }
    }

    private var aiResponseSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if isLoadingAIResponse {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text(NSLocalizedString("AI 正在生成...", comment: ""))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                } else if let error = aiErrorMessage {
                    Text(error)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ScrollView {
                        Text(aiResponseContent.isEmpty ? NSLocalizedString("暂无内容", comment: "") : aiResponseContent)
                            .font(.system(size: 16, design: .serif))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                }

                if canInsertAIContent {
                    Button(action: { insertAIContentIntoNote() }) {
                        Label(NSLocalizedString("highlight.action.insert_ai", comment: ""), systemImage: "note.text.badge.plus")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Spacer()

                adBannerSection
            }
            .padding()
            .navigationTitle(aiResponseTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("关闭", comment: "")) {
                        showingAIResponse = false
                        aiInsertionTarget = nil
                        aiActionInFlight = nil
                    }
                }
            }
        }
        .onDisappear {
            aiInsertionTarget = nil
        }
    }

    private func requestHighlightDeletion(_ highlight: Highlight, noteOnly: Bool) {
        pendingDeleteHighlight = highlight
        deletingNoteOnly = noteOnly
        showingDeleteConfirmation = true
    }

    private func handleHighlightDeletion() {
        guard let highlight = pendingDeleteHighlight else { return }

        if deletingNoteOnly {
            highlight.note = nil
            highlight.updatedAt = Date()
        } else {
            viewContext.delete(highlight)
        }

        do {
            try viewContext.save()
            if deletingNoteOnly {
                showHint(NSLocalizedString("highlight.action.delete_note_success", comment: ""))
            } else {
                showHint(NSLocalizedString("highlight.action.delete_highlight_success", comment: ""))
                activeHighlight = nil
                showingHighlightActions = false
            }
        } catch {
            DebugLogger.error("ReaderView: 删除高亮/笔记失败", error: error)
            showHint(NSLocalizedString("保存高亮失败", comment: ""))
        }

        pendingDeleteHighlight = nil
        deletingNoteOnly = false
    }

    private var adBannerSection: some View {
        Group {
            if let adUnit = AdMobAdUnitIDs.fixedBanner {
                BannerAdView(adUnitID: adUnit)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
            } else {
                Text(NSLocalizedString("广告位未配置", comment: ""))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(12)
            }
        }
    }

    private func hintBanner(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundColor(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 6)
            .padding(.horizontal, 20)
    }
    
    // MARK: - Helper Methods
    
    private var currentBookmark: Bookmark? {
        bookmarks.first { bookmark in
            Int(bookmark.chapterIndex) == currentChapterIndex &&
            Int(bookmark.pageIndex) == safeChapterPageIndex(currentChapterIndex)
        }
    }
    
    private func toggleBookmark() {
        guard !chapters.isEmpty, currentChapterIndex < chapters.count else { return }
        if let existing = currentBookmark {
            deleteBookmark(existing)
        } else {
            addBookmark()
        }
    }
    
    private func addBookmark() {
        ensurePageArrays()
        let bookmark = Bookmark(context: viewContext)
        bookmark.id = UUID()
        bookmark.createdAt = Date()
        bookmark.chapterIndex = Int32(currentChapterIndex)
        bookmark.pageIndex = Int32(safeChapterPageIndex(currentChapterIndex))
        bookmark.chapterTitle = chapters[currentChapterIndex].title
        bookmark.book = book
        
        do {
            try viewContext.save()
            DebugLogger.success("ReaderView: 已添加书签 - 章节 \(currentChapterIndex + 1)，页码 \(safeChapterPageIndex(currentChapterIndex) + 1)")
        } catch {
            DebugLogger.error("ReaderView: 添加书签失败", error: error)
        }
    }
    
    private func deleteBookmark(_ bookmark: Bookmark) {
        viewContext.delete(bookmark)
        do {
            try viewContext.save()
            DebugLogger.info("ReaderView: 已删除书签 - 章节 \(bookmark.chapterIndex + 1)，页码 \(bookmark.pageIndex + 1)")
        } catch {
            DebugLogger.error("ReaderView: 删除书签失败", error: error)
        }
    }
    
    private func handleTap() {
        let now = Date()
        if now.timeIntervalSince(lastTapTime) < 0.3 {
            // Double tap - do nothing or custom action
            return
        }
        lastTapTime = now
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            showingToolbar.toggle()
        }
    }
    
    private func loadBookContent() {
        isLoading = true
        loadError = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard let resolution = BookFileLocator.resolveFileURL(from: book.filePath) else {
                    DebugLogger.error("ReaderView: 无法找到书籍文件，存储路径: \(book.filePath)")
                    DispatchQueue.main.async {
                        self.loadError = NSLocalizedString("reader.error.file_missing", comment: "")
                        self.isLoading = false
                    }
                    return
                }
                
                let fileURL = resolution.url
                let normalizedPath = resolution.preferredStoredPath
                
                // Parse EPUB
                let metadata = try EPubParser.parseEPub(from: fileURL)
                
                DispatchQueue.main.async {
                    self.chapters = metadata.chapters
                    self.tocItems = metadata.tocItems
                    
                    if self.book.filePath != normalizedPath {
                        self.book.filePath = normalizedPath
                        do {
                            try self.viewContext.save()
                            DebugLogger.info("ReaderView: 已规范化书籍路径为 \(normalizedPath)")
                        } catch {
                            DebugLogger.error("ReaderView: 保存规范化书籍路径失败", error: error)
                        }
                    }
                    
                    if !applyInitialLocationIfAvailable() {
                        restoreReadingProgress()
                    }
                    
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.loadError = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func applyInitialLocationIfAvailable() -> Bool {
        guard let location = initialLocation, !didApplyInitialLocation else { return false }
        guard !chapters.isEmpty else { return false }
        didApplyInitialLocation = true
        
        let targetChapter = min(max(location.chapterIndex, 0), chapters.count - 1)
        ensurePageArrays()
        currentChapterIndex = targetChapter
        setChapterPageIndex(targetChapter, max(0, location.pageIndex))
        DebugLogger.info("ReaderView: 应用书签定位到章节 \(targetChapter + 1)，页码 \(safeChapterPageIndex(targetChapter) + 1)")
        return true
    }
    
    private func restoreReadingProgress() {
        guard let progress = book.readingProgress, !chapters.isEmpty else { return }
        currentChapterIndex = min(Int(progress.currentPage), chapters.count - 1)
        
        if let positionJSON = progress.currentPosition,
           let data = positionJSON.data(using: .utf8),
           let positionData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let savedChapterIndex = positionData["chapterIndex"] as? Int,
           let savedPageIndex = positionData["pageIndex"] as? Int {
            
            ensurePageArrays()
            
            if savedChapterIndex >= 0 && savedChapterIndex < chapters.count {
                currentChapterIndex = savedChapterIndex
                setChapterPageIndex(savedChapterIndex, savedPageIndex)
            } else {
                setChapterPageIndex(currentChapterIndex, savedPageIndex)
            }
        }
    }
    
    private func saveReadingProgress() {
        guard !chapters.isEmpty else { return }
        
        // Create or update reading progress
        if book.readingProgress == nil {
            let progress = ReadingProgress(context: viewContext)
            progress.id = UUID()
            progress.createdAt = Date()
            progress.updatedAt = Date()
            progress.totalReadingTime = 0
            progress.book = book
            book.readingProgress = progress
        }
        
        if let progress = book.readingProgress {
            progress.currentPage = Int32(currentChapterIndex)
            
            // Save the current page within chapter to currentPosition as JSON
            let positionData: [String: Any] = [
                "chapterIndex": currentChapterIndex,
                "pageIndex": safeChapterPageIndex(currentChapterIndex),
                "totalPages": safeChapterTotalPages(currentChapterIndex)
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: positionData),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                progress.currentPosition = jsonString
            }
            
            // Estimate percentage by chapter index and current page within chapter
            let chapterCount = max(chapters.count, 1)
            let base = Double(currentChapterIndex) / Double(chapterCount)
            let pageInChapter = Double(safeChapterPageIndex(currentChapterIndex))
            let totalInChapter = Double(max(safeChapterTotalPages(currentChapterIndex), 1))
            let perChapterWeight = 1.0 / Double(chapterCount)
            let within = (totalInChapter > 0) ? (pageInChapter / totalInChapter) * perChapterWeight : 0
            progress.progressPercentage = min(1.0, base + within)
            progress.lastReadAt = Date()
            progress.updatedAt = Date()
            
            // Update book's totalPages if needed
            if book.totalPages != Int32(chapters.count) {
                book.totalPages = Int32(chapters.count)
            }
            
            // Update reading status based on progress
            if let libraryItem = book.libraryItem {
                // Update lastAccessedAt
                libraryItem.lastAccessedAt = Date()
                
                // If progress reaches 100%, mark as finished
                if progress.progressPercentage >= 0.99 { // Use 0.99 to account for floating point precision
                    if libraryItem.status != .finished {
                        libraryItem.status = .finished
                        DebugLogger.info("ReaderView: Book completed! Updated status to 'finished'")
                    }
                } else if libraryItem.status == .wantToRead || libraryItem.status == .paused {
                    // If still reading (not finished), ensure status is "reading"
                    libraryItem.status = .reading
                }
            }
            
            do {
                try viewContext.save()
                print("✅ Reading progress saved: Chapter \(currentChapterIndex), Page \(safeChapterPageIndex(currentChapterIndex)), Progress: \(String(format: "%.1f%%", progress.progressPercentage * 100))")
            } catch {
                print("❌ Failed to save reading progress: \(error)")
            }
        }
    }
    
    private func checkFirstTimeOpen() {
        // 检查阅读进度，如果是新书或进度很少，则认为是首次打开
        if let progress = book.readingProgress {
            isFirstOpen = progress.progressPercentage < 0.05 // 小于5%认为是首次打开
        } else {
            isFirstOpen = true
        }
        
        // 如果是首次打开，延迟显示AI摘要以获得更好的用户体验
        if isFirstOpen {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    showingAISummary = true
                }
            }
        } else {
            showingAISummary = false
        }
    }

    // MARK: - Pagination helpers
    private func ensurePageArrays() {
        if chapterPageIndices.count != chapters.count {
            chapterPageIndices = Array(repeating: 0, count: max(chapters.count, 1))
        }
        if chapterTotalPages.count != chapters.count {
            chapterTotalPages = Array(repeating: 1, count: max(chapters.count, 1))
        }
    }
    
    private func safeChapterPageIndex(_ index: Int) -> Int {
        ensurePageArrays()
        guard index >= 0 && index < chapterPageIndices.count else { return 0 }
        return chapterPageIndices[index]
    }
    
    private func setChapterPageIndex(_ index: Int, _ value: Int) {
        ensurePageArrays()
        guard index >= 0 && index < chapterPageIndices.count else { return }
        chapterPageIndices[index] = max(0, value)
    }
    
    private func safeChapterTotalPages(_ index: Int) -> Int {
        ensurePageArrays()
        guard index >= 0 && index < chapterTotalPages.count else { return 1 }
        return max(1, chapterTotalPages[index])
    }
    
    private func setChapterTotalPages(_ index: Int, _ value: Int) {
        ensurePageArrays()
        guard index >= 0 && index < chapterTotalPages.count else { return }
        chapterTotalPages[index] = max(1, value)
        clampCurrentPage(index)
    }
    
    @discardableResult
    private func nextPageOrChapter(source: PageTurnSource) -> Bool {
        turnPage(.next, source: source)
    }
    
    @discardableResult
    private func previousPageOrChapter(source: PageTurnSource) -> Bool {
        turnPage(.previous, source: source)
    }
    
    @discardableResult
    private func turnPage(_ direction: PageTurnDirection, source: PageTurnSource) -> Bool {
        ensurePageArrays()
        var didMove = false
        
        // 在修改页码之前设置动画风格，确保 SwiftUI 在同一更新周期传递给 Coordinator
        pageTurnAnimationStyle = (source == .tap) ? .fade : .slide
        
        switch direction {
        case .next:
            let total = safeChapterTotalPages(currentChapterIndex)
            let page = safeChapterPageIndex(currentChapterIndex)
            if page < total - 1 {
                setChapterPageIndex(currentChapterIndex, page + 1)
                didMove = true
            } else if currentChapterIndex < chapters.count - 1 {
                currentChapterIndex += 1
                setChapterPageIndex(currentChapterIndex, 0)
                didMove = true
            }
        case .previous:
            let page = safeChapterPageIndex(currentChapterIndex)
            if page > 0 {
                setChapterPageIndex(currentChapterIndex, page - 1)
                didMove = true
            } else if currentChapterIndex > 0 {
                currentChapterIndex -= 1
                let lastPage = safeChapterTotalPages(currentChapterIndex) - 1
                setChapterPageIndex(currentChapterIndex, max(0, lastPage))
                didMove = true
            }
        }
        
        guard didMove else {
            provideBoundaryFeedback(for: direction)
            return false
        }
        
        saveReadingProgress()
        selectedTextInfo = nil
        provideTurnHaptic(for: source)
        return true
    }

    private func provideTurnHaptic(for source: PageTurnSource) {
        // 只在翻页时提供轻微的触觉反馈，保持简洁
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred(intensity: 0.5)
    }

    private func provideBoundaryFeedback(for direction: PageTurnDirection) {
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.warning)
        let key = direction == .next ? "reader.page_turn.reached_end" : "reader.page_turn.reached_start"
        showHint(NSLocalizedString(key, comment: ""))
    }
    
    // MARK: - Reading Time Tracking
    
    private func startReadingSession() {
        readingStartTime = Date()
        isActivelyReading = true
        
        // Update reading status to "reading" when user starts reading
        if let libraryItem = book.libraryItem {
            // Only update from "want to read" or "paused" to "reading"
            if libraryItem.status == .wantToRead || libraryItem.status == .paused {
                libraryItem.status = .reading
                libraryItem.lastAccessedAt = Date()
                
                do {
                    try viewContext.save()
                    DebugLogger.info("ReaderView: Updated status to 'reading'")
                } catch {
                    DebugLogger.error("ReaderView: Failed to update reading status: \(error)")
                }
            }
        }
    }
    
    private func endReadingSession() {
        updateReadingTime()
        readingStartTime = nil
        isActivelyReading = false
    }
    
    private func pauseReadingSession() {
        updateReadingTime()
        readingStartTime = nil
        isActivelyReading = false
    }
    
    private func resumeReadingSession() {
        readingStartTime = Date()
        isActivelyReading = true
    }
    
    private func updateReadingTime() {
        guard let startTime = readingStartTime, isActivelyReading else { return }
        
        let timeElapsed = Date().timeIntervalSince(startTime)
        
        // Only count if the reading session is meaningful (more than 1 second)
        guard timeElapsed > 1 else { return }
        
        // Create or get reading progress
        if book.readingProgress == nil {
            let progress = ReadingProgress(context: viewContext)
            progress.id = UUID()
            progress.createdAt = Date()
            progress.updatedAt = Date()
            progress.totalReadingTime = 0
            progress.book = book
            book.readingProgress = progress
        }
        
        if let progress = book.readingProgress {
            // Add elapsed time to total
            progress.totalReadingTime += Int64(timeElapsed)
            progress.updatedAt = Date()
            
            do {
                try viewContext.save()
            } catch {
                print("Failed to save reading time: \(error)")
            }
        }
    }
    
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            // Resume tracking when app becomes active
            if !isActivelyReading {
                resumeReadingSession()
            }
        case .inactive:
            // Save reading progress and pause tracking when app becomes inactive
            saveReadingProgress()
            if isActivelyReading {
                pauseReadingSession()
            }
        case .background:
            // Save reading progress and reading time when app goes to background
            saveReadingProgress()
            if isActivelyReading {
                pauseReadingSession()
            }
        @unknown default:
            break
        }
    }

    private func clampCurrentPage(_ index: Int) {
        let total = safeChapterTotalPages(index)
        let page = safeChapterPageIndex(index)
        if total == 0 {
            setChapterTotalPages(index, 1)
            setChapterPageIndex(index, 0)
        } else if page >= total {
            setChapterPageIndex(index, max(0, total - 1))
        }
    }
    
    // MARK: - 滑动手势处理
    private func handleNavigationTap(at location: CGPoint, geometry: GeometryProxy) {
        if shouldIgnoreNavigationTap() {
            return
        }
        guard selectedTextInfo == nil else { return }

        let width = max(geometry.size.width, 1)
        let normalizedX = location.x / width

        // 边缘点击（翻页）：立即执行，零延迟，最大化响应速度
        if normalizedX < tapNavigationEdgeRatio {
            pendingTapWorkItem?.cancel()
            pendingTapWorkItem = nil
            _ = previousPageOrChapter(source: .tap)
            return
        } else if normalizedX > (1 - tapNavigationEdgeRatio) {
            pendingTapWorkItem?.cancel()
            pendingTapWorkItem = nil
            _ = nextPageOrChapter(source: .tap)
            return
        }

        // 中间区域（工具栏切换）：保留双击检测防止误触
        let doubleTapInterval: TimeInterval = 0.18
        let now = Date()
        if let lastTap = lastNavigationTapTime, now.timeIntervalSince(lastTap) < doubleTapInterval {
            pendingTapWorkItem?.cancel()
            pendingTapWorkItem = nil
            lastNavigationTapTime = nil
            return
        }

        lastNavigationTapTime = now
        pendingTapWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            if self.shouldIgnoreNavigationTap() { return }
            self.handleTap()
        }
        pendingTapWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapInterval, execute: workItem)
    }

    private func suppressNavigationForWebContentTap() {
        lastWebContentTapTime = Date()
        pendingTapWorkItem?.cancel()
        pendingTapWorkItem = nil
        lastNavigationTapTime = nil
    }

    private func shouldIgnoreNavigationTap() -> Bool {
        if showingHighlightActions {
            return true
        }
        if let lastWebTap = lastWebContentTapTime, Date().timeIntervalSince(lastWebTap) < 0.5 {
            return true
        }
        return false
    }
    
    private func handleDragChanged(_ value: DragGesture.Value, geometry: GeometryProxy) {
        guard swipePagingEnabled else { return }
        guard !isInteractingWithWebContent else { return }
        // 防止在动画过程中处理新的拖拽
        guard !isAnimatingPageTurn else { return }
        pendingTapWorkItem?.cancel()

        let translation = value.translation
        let startLocation = value.startLocation

        // 检查是否是水平滑动（水平移动距离大于垂直移动距离）
        if abs(translation.width) > abs(translation.height) && abs(translation.width) > 10 {
            if !isDragging {
                isDragging = true
                dragStartLocation = startLocation

                // 隐藏工具栏以获得更好的滑动体验
                if showingToolbar {
                    withAnimation(.easeOut(duration: 0.15)) {
                        showingToolbar = false
                    }
                }
            }

            // 计算拖拽偏移，添加阻尼效果 - 简化计算以提升性能
            let maxOffset = geometry.size.width * 0.2
            let dampingFactor: CGFloat = 0.5
            let rawOffset = translation.width * dampingFactor

            // 检查是否可以翻页
            let canGoNext = canNavigateToNextPage()
            let canGoPrevious = canNavigateToPreviousPage()

            if rawOffset > 0 && !canGoPrevious {
                // 向右滑动但无法向前翻页，增加阻力
                dragOffset = min(rawOffset * 0.25, maxOffset * 0.25)
            } else if rawOffset < 0 && !canGoNext {
                // 向左滑动但无法向后翻页，增加阻力
                dragOffset = max(rawOffset * 0.25, -maxOffset * 0.25)
            } else {
                // 正常滑动
                dragOffset = max(-maxOffset, min(maxOffset, rawOffset))
            }
        }
    }
    
    private func handleDragEnded(_ value: DragGesture.Value, geometry: GeometryProxy) {
        let tapThreshold: CGFloat = 10
        let isTapLike = abs(value.translation.width) < tapThreshold && abs(value.translation.height) < tapThreshold

        if isTapLike {
            isDragging = false
            dragOffset = 0
            guard selectedTextInfo == nil else { return }
            handleNavigationTap(at: value.startLocation, geometry: geometry)
            return
        }

        if !swipePagingEnabled {
            dragOffset = 0
            isDragging = false
            return
        }

        guard !isInteractingWithWebContent else {
            dragOffset = 0
            isDragging = false
            return
        }
        guard isDragging else {
            dragOffset = 0
            return
        }

        let translation = value.translation
        let velocity = CGPoint(
            x: value.predictedEndTranslation.width - value.translation.width,
            y: value.predictedEndTranslation.height - value.translation.height
        )

        // 判断翻页阈值 - 降低阈值以获得更灵敏的响应
        let threshold = geometry.size.width * 0.15
        let velocityThreshold: CGFloat = 200

        let shouldTurnPage = abs(translation.width) > threshold || abs(velocity.x) > velocityThreshold

        if shouldTurnPage && abs(translation.width) > abs(translation.height) {
            if translation.width > 0 && canNavigateToPreviousPage() {
                // 向右滑动，翻到上一页
                performPageTurn(direction: .previous)
            } else if translation.width < 0 && canNavigateToNextPage() {
                // 向左滑动，翻到下一页
                performPageTurn(direction: .next)
            } else {
                // 无法翻页，回弹
                animateBackToOriginalPosition()
            }
        } else {
            // 滑动距离不够，回弹
            animateBackToOriginalPosition()
        }

        isDragging = false
    }
    
    private func performPageTurn(direction: PageTurnDirection) {
        guard !isAnimatingPageTurn else { return }

        let didTurn: Bool
        switch direction {
        case .next:
            didTurn = nextPageOrChapter(source: .swipe)
        case .previous:
            didTurn = previousPageOrChapter(source: .swipe)
        }

        guard didTurn else {
            animateBackToOriginalPosition()
            return
        }

        isAnimatingPageTurn = true

        // 使用更快速的弹簧动画归位
        withAnimation(.spring(response: 0.2, dampingFraction: 0.85, blendDuration: 0)) {
            dragOffset = 0
        }

        // 缩短动画锁定时间
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.isAnimatingPageTurn = false
        }
    }
    
    private func animateBackToOriginalPosition() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            dragOffset = 0
        }
    }
    
    private func canNavigateToNextPage() -> Bool {
        ensurePageArrays()
        let total = safeChapterTotalPages(currentChapterIndex)
        let page = safeChapterPageIndex(currentChapterIndex)
        return page < total - 1 || currentChapterIndex < chapters.count - 1
    }
    
    private func canNavigateToPreviousPage() -> Bool {
        ensurePageArrays()
        let page = safeChapterPageIndex(currentChapterIndex)
        return page > 0 || currentChapterIndex > 0
    }

    private enum PageTurnSource {
        case tap
        case swipe
    }
    
    private enum PageTurnDirection {
        case next
        case previous
    }
    
    // MARK: - 滑动视觉反馈

    private func slideVisualFeedback(geometry: GeometryProxy) -> some View {
        // 简化的视觉反馈：只保留边缘发光效果，提升性能
        edgeGlowEffect(geometry: geometry)
            .allowsHitTesting(false)
    }

    private func edgeGlowEffect(geometry: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            if dragOffset > 0 {
                // 左边缘发光
                LinearGradient(
                    gradient: Gradient(colors: [
                        canNavigateToPreviousPage() ? Color.blue.opacity(0.2) : Color.gray.opacity(0.15),
                        Color.clear
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 6)
                .opacity(min(abs(dragOffset) / 80.0, 1.0))

                Spacer()
            } else {
                Spacer()

                // 右边缘发光
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        canNavigateToNextPage() ? Color.blue.opacity(0.2) : Color.gray.opacity(0.15)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 6)
                .opacity(min(abs(dragOffset) / 80.0, 1.0))
            }
        }
    }
}

private struct SelectionAnchor: Codable {
    let chapterIndex: Int
    let pageIndex: Int
    let offset: Int
}

struct TableOfContentsView: View {
    let tocItems: [TOCItem]
    let chapters: [Chapter]
    @Binding var currentChapterIndex: Int
    @Environment(\.dismiss) private var dismiss
    
    private struct DisplayItem: Identifiable {
        let id: Int
        let title: String
        let chapterIndex: Int
        let level: Int
    }
    
    private var displayItems: [DisplayItem] {
        if !tocItems.isEmpty {
            return tocItems.enumerated().map { index, item in
                DisplayItem(id: index, title: item.title, chapterIndex: item.chapterIndex, level: item.level)
            }
        }
        
        return chapters.enumerated().map { index, chapter in
            DisplayItem(id: index, title: chapter.title, chapterIndex: index, level: 0)
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(displayItems) { item in
                        Button(action: {
                            currentChapterIndex = item.chapterIndex
                            dismiss()
                        }) {
                            HStack(spacing: 12) {
                                // Chapter number indicator
                                ZStack {
                                    Circle()
                                        .fill(item.chapterIndex == currentChapterIndex ?
                                              LinearGradient(gradient: Gradient(colors: [.blue, .blue.opacity(0.7)]), 
                                                           startPoint: .topLeading, 
                                                           endPoint: .bottomTrailing) :
                                              LinearGradient(gradient: Gradient(colors: [.gray.opacity(0.2), .gray.opacity(0.1)]), 
                                                           startPoint: .topLeading, 
                                                           endPoint: .bottomTrailing))
                                        .frame(width: 36, height: 36)
                                    
                                    Text("\(item.id + 1)")
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundColor(item.chapterIndex == currentChapterIndex ? .white : .secondary)
                                }
                                
                                // Chapter title
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.system(size: 16, weight: .medium, design: .serif))
                                        .foregroundColor(.primary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    
                                    if item.chapterIndex == currentChapterIndex {
                                        Text(NSLocalizedString("当前章节", comment: ""))
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundColor(.blue)
                                    }
                                }
                                
                                Spacer()
                                
                                if item.chapterIndex == currentChapterIndex {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.leading, CGFloat(item.level) * 16)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .id(item.id)
                    }
                }
                .listStyle(.insetGrouped)
                .onAppear {
                    // Scroll to current chapter
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        scrollToCurrent(in: proxy)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("目录", comment: ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Text(NSLocalizedString("完成", comment: ""))
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.medium)
                    }
                }
            }
        }
    }
    
    private func scrollToCurrent(in proxy: ScrollViewProxy) {
        guard let target = displayItems.first(where: { $0.chapterIndex == currentChapterIndex }) else { return }
        withAnimation {
            proxy.scrollTo(target.id, anchor: .center)
        }
    }
}

struct ReaderSettingsView: View {
    @StateObject private var appSettings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section(NSLocalizedString("字体设置", comment: "")) {
                    HStack {
                        Text(NSLocalizedString("字体大小", comment: ""))
                        Spacer()
                        Picker(NSLocalizedString("字体大小", comment: ""), selection: $appSettings.readingFontSize) {
                            ForEach(ReadingFontSize.allCases, id: \.rawValue) { size in
                                Text(size.displayName).tag(size)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                }
                
                Section(NSLocalizedString("排版设置", comment: "")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(NSLocalizedString("行间距", comment: ""))
                            Spacer()
                            Text(String(format: "%.1f", appSettings.lineSpacing))
                                .foregroundColor(.secondary)
                        }
                        
                        Slider(value: $appSettings.lineSpacing, in: 1.0...2.0, step: 0.1)
                            .accentColor(.blue)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(NSLocalizedString("页面边距", comment: ""))
                            Spacer()
                            Text("\(Int(appSettings.pageMargins))pt")
                                .foregroundColor(.secondary)
                        }
                        
                        Slider(value: $appSettings.pageMargins, in: 10...40, step: 5)
                            .accentColor(.blue)
                    }
                }
                
                Section(NSLocalizedString("主题", comment: "")) {
                    Picker(NSLocalizedString("主题", comment: ""), selection: $appSettings.theme) {
                        ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
            }
            .navigationTitle(NSLocalizedString("阅读设置", comment: ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Text(NSLocalizedString("完成", comment: ""))
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.medium)
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { dismiss() }) {
                        Text(NSLocalizedString("完成", comment: ""))
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.medium)
                    }
                }
                #endif
            }
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let book = Book(context: context)
    book.id = UUID()
    book.title = "示例书籍"
    book.filePath = "/dev/null"
    book.fileFormat = "txt"
    book.fileSize = 0
    book.checksum = UUID().uuidString
    book.totalPages = 1
    book.createdAt = Date()
    book.updatedAt = Date()
    return ReaderView(book: book)
        .environment(\.managedObjectContext, context)
}
