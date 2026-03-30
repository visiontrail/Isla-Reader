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
    @State private var currentTOCFragment: String?
    @State private var tocNavigationToken: Int = 0
    @State private var pendingTOCNavigation: TOCNavigationRequest?
    @State private var highlightNavigationToken: Int = 0
    @State private var pendingHighlightNavigation: HighlightNavigationRequest?
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
    @State private var customAIQuestionDraft = ""
    @State private var showingSelectionAskComposer = false
    @State private var selectionAskSourceText = ""
    @State private var aiResponseTitle = ""
    @State private var aiResponseContent = ""
    @State private var aiActionInFlight: AIAction?
    @State private var aiInsertionTarget: AIInsertionTarget?
    @State private var isLoadingAIResponse = false
    @State private var aiErrorMessage: String?
    @State private var activeHighlight: Highlight?
    @State private var activeHighlightText: String = ""
    @State private var showingHighlightActions = false
    @State private var showingHighlightNoteEditor = false
    @State private var highlightNoteDraft = ""
    @State private var noteDraftHighlightObjectID: NSManagedObjectID?
    @State private var showingHighlightAskComposer = false
    @State private var highlightAIQuestionDraft = ""
    @State private var pendingDeleteHighlight: Highlight?
    @State private var deletingNoteOnly = false
    @State private var showingDeleteConfirmation = false
    @State private var hintMessage: String?
    @State private var showingHighlightsList = false
    @State private var showingBookmarksList = false
    @State private var selectionToolbarMeasuredHeight: CGFloat = 0
    @State private var didApplyInitialLocation = false
    @State private var hasReportedInitialChapterOpenMetric = false
    @State private var pendingSelectionClearWorkItem: DispatchWorkItem?
    
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
    @State private var lastSelectionInteractionTime: Date?
    @State private var lastSwipeTurnTime: Date?
    @State private var keyboardHeight: CGFloat = 0
    @FocusState private var isCustomQuestionFieldFocused: Bool
    @FocusState private var isHighlightNoteEditorFocused: Bool
    @FocusState private var isHighlightQuestionFieldFocused: Bool
    private let swipePagingEnabled = true
    private let tapNavigationEdgeRatio: CGFloat = 0.24
    private let chapterPreloadWindow = 2
    @State private var pageTurnAnimationStyle: PageTurnAnimationStyle = .fade
    
    private var effectiveColorScheme: ColorScheme {
        appSettings.theme.colorScheme ?? systemColorScheme
    }

    private enum AIAction {
        case translate
        case explain
        case custom(question: String)
    }

    private enum AIInsertionTarget {
        case selection
        case highlight(Highlight)
    }
    
    // Pagination states per chapter
    @State private var chapterPageIndices: [Int] = []
    @State private var chapterTotalPages: [Int] = []
    @State private var chapterPageCountsMeasured: [Bool] = []
    
    // Reading time tracking
    @State private var readingStartTime: Date?
    @State private var isActivelyReading: Bool = false
    @State private var readingHeartbeatTask: Task<Void, Never>?
    @State private var lastPublishedLiveActivityMinute: Int = -1
    private let readingHeartbeatIntervalNanoseconds: UInt64 = 15_000_000_000
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
            TableOfContentsView(
                tocItems: tocItems,
                chapters: chapters,
                currentChapterIndex: $currentChapterIndex,
                currentTOCFragment: $currentTOCFragment,
                onSelectTOCItem: handleTOCSelection
            )
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
        .sheet(isPresented: $showingSelectionAskComposer) {
            selectionAskComposerSheet
        }
        .sheet(isPresented: $showingHighlightActions) {
            highlightActionSheet
        }
        .fullScreenCover(isPresented: $showingHighlightsList) {
            HighlightListSheet(book: book) { location in
                navigateTo(location: location)
            }
        }
        .sheet(isPresented: $showingBookmarksList) {
            BookmarkListSheet(book: book) { location in
                navigateTo(location: location)
            }
        }
        .overlay(alignment: .top) {
            if let hintMessage {
                hintBanner(hintMessage)
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            reportBookOpenMetric()
            loadBookContent()
            startReadingSession()
            startReadingHeartbeat()
            syncLiveActivityReadingProgressIfNeeded(reason: "onAppear")
        }
        .onDisappear {
            // Save reading progress when view disappears (e.g., user navigates back)
            stopReadingHeartbeat()
            saveReadingProgress()
            endReadingSession()
            pendingTapWorkItem?.cancel()
            pendingSelectionClearWorkItem?.cancel()
        }
        .onChange(of: scenePhase) { newPhase in
            handleScenePhaseChange(newPhase)
        }
        .onChange(of: currentChapterIndex) { _ in
            // Save progress when chapter changes
            saveReadingProgress()
            reportChapterOpenMetric()
            selectedTextInfo = nil
            if pendingTOCNavigation?.chapterIndex != currentChapterIndex {
                currentTOCFragment = nil
            }
            preloadNearbyChapterHTML(around: currentChapterIndex)
        }
        .onChange(of: appSettings.readingFontSize) { _ in
            preloadNearbyChapterHTML(around: currentChapterIndex)
        }
        .onChange(of: appSettings.lineSpacing) { _ in
            preloadNearbyChapterHTML(around: currentChapterIndex)
        }
        .onChange(of: appSettings.pageMargins) { _ in
            preloadNearbyChapterHTML(around: currentChapterIndex)
        }
        .onChange(of: selectedTextInfo) { info in
            if info == nil, !showingSelectionAskComposer {
                customAIQuestionDraft = ""
                isCustomQuestionFieldFocused = false
            }
        }
        .onChange(of: effectiveColorScheme) { _ in
            preloadNearbyChapterHTML(around: currentChapterIndex)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            handleKeyboardFrameChange(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
            handleKeyboardFrameChange(notification)
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
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {
                pendingDeleteHighlight = nil
                deletingNoteOnly = false
            }
        }
    }
    
    // MARK: - View Components
    
    private var backgroundView: some View {
        Group {
            if effectiveColorScheme == .dark {
                Color(red: 0.05, green: 0.05, blue: 0.07)
            } else {
                Color(red: 0.98, green: 0.98, blue: 0.98)
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.primary.opacity(0.6))
            
            Text(NSLocalizedString("reader.loading_book", comment: ""))
                .font(.system(.body, design: .rounded))
                .foregroundColor(.secondary)
        }
    }
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text(NSLocalizedString("reader.load_failed", comment: ""))
                .font(.system(.title2, design: .rounded))
                .fontWeight(.semibold)
            
            Text(error)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(action: { dismiss() }) {
                Text(NSLocalizedString("common.back", comment: ""))
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
                        .id("\(book.id.uuidString)-\(currentChapterIndex)")
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

    private var currentChapterTitle: String {
        guard chapters.indices.contains(currentChapterIndex) else { return "" }
        let trimmed = chapters[currentChapterIndex].title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed
    }

    private var shouldShowInlineChapterTitle: Bool {
        !showingToolbar && !currentChapterTitle.isEmpty
    }

    private var inlineChapterTitleView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(currentChapterTitle)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .padding(.horizontal, CGFloat(max(20.0, appSettings.pageMargins)))

            // Keep one blank line between chapter title and reading content.
            Color.clear
                .frame(height: appSettings.readingFontSize.fontSize)
        }
        .padding(.top, 6)
        .allowsHitTesting(false)
    }

    private var isSelectionInputSessionActive: Bool {
        isCustomQuestionFieldFocused ||
        isHighlightQuestionFieldFocused ||
        showingSelectionAskComposer ||
        showingHighlightAskComposer
    }

    private func chapterView(index: Int, chapter: Chapter, geometry: GeometryProxy) -> some View {
        ZStack {
            // Content WebView with horizontal pagination
            // 为页码显示预留空间：页码高度约50px（包括padding和背景）
            let pageIndicatorHeight: CGFloat = 36
            let webViewHeight = geometry.size.height - pageIndicatorHeight
            let activeTOCNavigation = pendingTOCNavigation?.chapterIndex == index ? pendingTOCNavigation : nil
            let activeHighlightNavigation = pendingHighlightNavigation?.chapterIndex == index ? pendingHighlightNavigation : nil
            
            ReaderWebView(
                contentID: readerContentID(for: chapter),
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
                tocNavigationFragment: activeTOCNavigation?.fragment,
                tocNavigationToken: activeTOCNavigation?.token ?? 0,
                highlightTextOffset: activeHighlightNavigation?.textOffset,
                highlightNavigationToken: activeHighlightNavigation?.token ?? 0,
                pageTurnStyle: pageTurnAnimationStyle,
                isSelectionInputFocused: isSelectionInputSessionActive,
                onToolbarToggle: {
                    handleTap()
                },
                onTextSelection: { info in
                    guard !isSelectionInputSessionActive else { return }
                    lastSelectionInteractionTime = Date()
                    let trimmed = info.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        guard !showingSelectionAskComposer else { return }
                        pendingSelectionClearWorkItem?.cancel()
                        let clearTask = DispatchWorkItem {
                            self.selectedTextInfo = nil
                        }
                        pendingSelectionClearWorkItem = clearTask
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: clearTask)
                    } else {
                        pendingSelectionClearWorkItem?.cancel()
                        pendingSelectionClearWorkItem = nil
                        pendingTapWorkItem?.cancel()
                        let updatedInfo = SelectedTextInfo(
                            text: trimmed,
                            startOffset: info.startOffset,
                            endOffset: info.endOffset,
                            rect: info.rect,
                            pageIndex: info.pageIndex,
                            canContinueToNextPage: info.canContinueToNextPage,
                            isSplitParagraphTailRegion: info.isSplitParagraphTailRegion
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
            
            // 滑动视觉反馈
            if isDragging {
                slideVisualFeedback(geometry: geometry)
            }
            
            if safeChapterTotalPages(index) > 1 {
                VStack {
                    Spacer()
                        .frame(height: webViewHeight)

                    HStack {
                        Spacer()
                        Text("\(safeChapterPageIndex(index) + 1) / \(safeChapterTotalPages(index))")
                            .font(.system(size: 11, weight: .regular, design: .default))
                            .foregroundColor(.secondary.opacity(0.7))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                        Spacer()
                    }
                    .frame(height: pageIndicatorHeight)
                }
                .transition(.opacity)
            }

            if let info = selectedTextInfo {
                selectionToolbar(for: info, in: geometry)
            }

            if shouldShowInlineChapterTitle {
                VStack(spacing: 0) {
                    inlineChapterTitleView
                    Spacer()
                }
                .frame(width: geometry.size.width, height: webViewHeight, alignment: .top)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
    
    private func normalizeTOCFragment(_ fragment: String?) -> String? {
        guard let fragment else { return nil }
        let cleaned = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return cleaned.hasPrefix("#") ? String(cleaned.dropFirst()) : cleaned
    }

    private func preloadNearbyChapterHTML(around index: Int) {
        guard !chapters.isEmpty else { return }
        guard chapters.indices.contains(index) else { return }

        let minIndex = max(0, index - 1)
        let maxIndex = min(chapters.count - 1, index + chapterPreloadWindow)
        let candidateIndices = Array(minIndex...maxIndex)

        for chapterIndex in candidateIndices {
            let chapter = chapters[chapterIndex]
            ReaderWebView.preloadChapterHTML(
                contentID: readerContentID(for: chapter),
                htmlContent: chapter.htmlContent,
                fontSize: appSettings.readingFontSize.fontSize,
                lineSpacing: appSettings.lineSpacing,
                isDarkMode: effectiveColorScheme == .dark,
                pageMargins: Int(appSettings.pageMargins)
            )
        }
    }

    private func handleTOCSelection(chapterIndex: Int, fragment: String?) {
        let normalizedFragment = normalizeTOCFragment(fragment)
        currentChapterIndex = chapterIndex
        currentTOCFragment = normalizedFragment

        tocNavigationToken += 1
        pendingTOCNavigation = TOCNavigationRequest(
            chapterIndex: chapterIndex,
            fragment: normalizedFragment,
            token: tocNavigationToken
        )
    }

    private func readerContentID(for chapter: Chapter) -> String {
        ReaderWebView.makeContentID(bookID: book.id, chapterOrder: chapter.order)
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
                toolbarButton(icon: "highlighter", action: { openHighlightsAndNotes() })
                bookmarkListToolbarButton
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

    private var bookmarkListToolbarButton: some View {
        Button(action: { openBookmarksList() }) {
            ZStack {
                Image(systemName: "bookmark")
                    .font(.system(size: 17, weight: .light))
                    .foregroundColor(.primary.opacity(0.25))
                    .offset(x: -4, y: 3)
                Image(systemName: "bookmark")
                    .font(.system(size: 17, weight: .light))
                    .foregroundColor(.primary.opacity(0.5))
                    .offset(x: -2, y: 1.5)
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.clear)
            )
        }
    }

    // MARK: - Selection & Notes

    private func selectionToolbar(for info: SelectedTextInfo, in geometry: GeometryProxy) -> some View {
        let toolbarWidth = min(max(geometry.size.width - 16, 320), 820)
        let canContinueSelection = shouldShowContinueSelectionButton(for: info)
        let panelOnTop = shouldPlaceSelectionPanelAtTop(for: info, in: geometry, canContinueSelection: canContinueSelection)
        let panelAlignment: Alignment = panelOnTop ? .top : .bottom
        let toolbarTopPadding = geometry.safeAreaInsets.top + (showingToolbar ? 88 : 12)
        let toolbarBottomPadding = geometry.safeAreaInsets.bottom + (showingToolbar ? 124 : 12)

        return VStack(spacing: 12) {
            if canContinueSelection {
                Button(action: continueSelectionToNextPage) {
                    Label(NSLocalizedString("reader.selection.continue_next_page", comment: ""), systemImage: "arrow.right.circle.fill")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.88), Color.cyan.opacity(0.82)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.top, 6)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    selectionActionButton(
                        title: NSLocalizedString("reader.highlight.action", comment: ""),
                        systemImage: "highlighter",
                        tint: .yellow.opacity(0.9),
                        action: { commitHighlight(note: nil) }
                    )

                    selectionActionButton(
                        title: NSLocalizedString("reader.note.add", comment: ""),
                        systemImage: "note.text",
                        tint: .blue.opacity(0.9),
                        action: { prepareNoteEditor() }
                    )

                    selectionActionButton(
                        title: NSLocalizedString("reader.ai.explain", comment: ""),
                        systemImage: "brain.head.profile",
                        tint: .purple,
                        action: { startAIRequest(.explain) }
                    )

                    selectionActionButton(
                        title: NSLocalizedString("reader.ai.translate", comment: ""),
                        systemImage: "globe",
                        tint: .green,
                        action: { startAIRequest(.translate) }
                    )

                    selectionActionButton(
                        title: NSLocalizedString("common.copy", comment: ""),
                        systemImage: "doc.on.doc",
                        tint: .secondary,
                        action: { handleCopySelectedText() }
                    )
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 4)
            }

            Button(action: openSelectionAskComposer) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.blue.opacity(0.9))
                        .frame(width: 24, height: 24)

                    Text(NSLocalizedString("reader.ai.question.placeholder", comment: ""))
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(Color.blue.opacity(0.9))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.68))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .frame(width: toolbarWidth)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.primary.opacity(0.09))
        )
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SelectionToolbarHeightPreferenceKey.self,
                    value: proxy.size.height
                )
            }
        )
        .onPreferenceChange(SelectionToolbarHeightPreferenceKey.self) { measuredHeight in
            guard measuredHeight.isFinite, measuredHeight > 0 else { return }
            guard abs(selectionToolbarMeasuredHeight - measuredHeight) > 0.5 else { return }
            selectionToolbarMeasuredHeight = measuredHeight
        }
        .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: panelAlignment)
        .padding(.top, panelOnTop ? toolbarTopPadding : 0)
        .padding(.bottom, panelOnTop ? 0 : toolbarBottomPadding)
        .transition(.move(edge: panelOnTop ? .top : .bottom).combined(with: .opacity))
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.84, blendDuration: 0.08), value: selectedTextInfo)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.84, blendDuration: 0.08), value: panelOnTop)
    }

    private var selectionAskComposerSheet: some View {
        let trimmedQuestion = customAIQuestionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let canSubmitQuestion = !trimmedQuestion.isEmpty && !isLoadingAIResponse
        let quoteText = selectionAskSourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedText = quoteText.isEmpty ? NSLocalizedString("common.no_content", comment: "") : quoteText

        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(NSLocalizedString("reader.selection.title", comment: ""), systemImage: "quote.opening")
                            .font(.footnote)
                            .foregroundColor(.secondary)

                        Text(resolvedText)
                            .font(.system(size: 16, design: .serif))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(12)
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .navigationTitle(NSLocalizedString("reader.ai.ask", comment: ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("common.close", comment: "")) {
                        dismissSelectionAskComposer(clearDraft: true)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.blue.opacity(0.9))
                        .frame(width: 24, height: 24)

                    TextField(
                        NSLocalizedString("reader.ai.question.placeholder", comment: ""),
                        text: $customAIQuestionDraft
                    )
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.send)
                    .focused($isCustomQuestionFieldFocused)
                    .onSubmit {
                        submitSelectionCustomAIQuestion()
                    }

                    Button {
                        submitSelectionCustomAIQuestion()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(canSubmitQuestion ? Color.blue : Color.secondary.opacity(0.22))
                                .frame(width: 30, height: 30)
                            Image(systemName: "arrow.up")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .disabled(!canSubmitQuestion)
                    .accessibilityLabel(NSLocalizedString("reader.ai.question.send", comment: ""))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Divider()
                        .opacity(0.55)
                }
            }
        }
        .onAppear {
            scheduleSelectionQuestionFieldFocus()
        }
        .onDisappear {
            isCustomQuestionFieldFocused = false
        }
    }

    private func shouldShowContinueSelectionButton(for info: SelectedTextInfo) -> Bool {
        guard info.canContinueToNextPage else { return false }
        guard chapters.indices.contains(currentChapterIndex) else { return false }
        return info.pageIndex == safeChapterPageIndex(currentChapterIndex)
    }

    private func continueSelectionToNextPage() {
        guard let info = selectedTextInfo, shouldShowContinueSelectionButton(for: info) else { return }
        suppressNavigationForWebContentTap()
        let action = ReaderSelectionAction(type: .continueToNextPage)
        selectionAction = action
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            if self.selectionAction?.id == action.id {
                self.selectionAction = nil
            }
        }
    }

    private func selectionActionButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(tint)
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.65))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func selectionPreviewCard(
        text: String,
        maxHeight: CGFloat,
        lineLimit: Int,
        minHeight: CGFloat = 0,
        title: String = NSLocalizedString("reader.selection.title", comment: "")
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote)
                .foregroundColor(.secondary)

            Text(text)
                .font(.system(size: 16, design: .serif))
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(lineLimit)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: minHeight, maxHeight: maxHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
        )
    }
    private func selectionToolbarEstimatedHeight(canContinueSelection: Bool) -> CGFloat {
        let fallbackHeight: CGFloat = canContinueSelection ? 230 : 188
        return max(selectionToolbarMeasuredHeight, fallbackHeight)
    }

    private func shouldPlaceSelectionPanelAtTop(
        for info: SelectedTextInfo,
        in geometry: GeometryProxy,
        canContinueSelection: Bool
    ) -> Bool {
        let hasFiniteRect =
            info.rect.minX.isFinite &&
            info.rect.minY.isFinite &&
            info.rect.width.isFinite &&
            info.rect.height.isFinite &&
            info.rect != .zero
        guard hasFiniteRect else { return false }

        let topReserved = geometry.safeAreaInsets.top + (showingToolbar ? 88 : 12)
        let bottomReserved = geometry.safeAreaInsets.bottom + (showingToolbar ? 124 : 12)
        let safeTop = topReserved
        let safeBottom = max(safeTop + 1, geometry.size.height - bottomReserved)
        let panelHeight = selectionToolbarEstimatedHeight(canContinueSelection: canContinueSelection)
        let panelClearance: CGFloat = 14
        let topPanelMaxY = min(safeBottom, safeTop + panelHeight + panelClearance)
        let bottomPanelMinY = max(safeTop, safeBottom - panelHeight - panelClearance)

        let selectionMinY = min(max(info.rect.minY, safeTop), safeBottom)
        let selectionMaxY = min(max(info.rect.maxY, safeTop), safeBottom)
        guard selectionMaxY > selectionMinY else { return false }

        let topOverlap = max(0, min(selectionMaxY, topPanelMaxY) - selectionMinY)
        let bottomOverlap = max(0, selectionMaxY - max(selectionMinY, bottomPanelMinY))
        let overlapBias: CGFloat = 2

        if bottomOverlap > topOverlap + overlapBias {
            return true
        }
        if topOverlap > bottomOverlap + overlapBias {
            return false
        }

        let gapToTopPanel = max(0, selectionMinY - topPanelMaxY)
        let gapToBottomPanel = max(0, bottomPanelMinY - selectionMaxY)
        if gapToBottomPanel < gapToTopPanel {
            return true
        }
        if gapToTopPanel < gapToBottomPanel {
            return false
        }

        let selectionMidY = (selectionMinY + selectionMaxY) * 0.5
        let threshold = safeTop + (safeBottom - safeTop) * 0.56
        return selectionMidY >= threshold
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
            showHint(NSLocalizedString("reader.selection.required", comment: ""))
            return
        }
        noteDraft = ""
        showingNoteEditor = true
    }

    private func openHighlightsAndNotes() {
        showingHighlightsList = true
    }

    private func openBookmarksList() {
        showingBookmarksList = true
    }

    private func navigateTo(location: BookmarkLocation) {
        guard !chapters.isEmpty else {
            DebugLogger.warning("[HighlightNav] navigateTo: chapters 为空，跳过")
            return
        }

        let targetChapter = min(max(location.chapterIndex, 0), chapters.count - 1)
        let targetFragment = normalizeTOCFragment(location.tocFragment)
        ensurePageArrays()
        currentChapterIndex = targetChapter
        setChapterPageIndex(targetChapter, max(0, location.pageIndex))
        DebugLogger.info("[HighlightNav] navigateTo: 设置 chapter=\(targetChapter), 初始page=\(location.pageIndex)")

        currentTOCFragment = targetFragment
        if let targetFragment {
            tocNavigationToken += 1
            pendingTOCNavigation = TOCNavigationRequest(
                chapterIndex: targetChapter,
                fragment: targetFragment,
                token: tocNavigationToken
            )
            DebugLogger.info("ReaderView: navigateTo 设置 TOC fragment=\(targetFragment), token=\(tocNavigationToken)")
        } else {
            pendingTOCNavigation = nil
        }

        if let textOffset = location.textOffset {
            highlightNavigationToken += 1
            pendingHighlightNavigation = HighlightNavigationRequest(
                chapterIndex: targetChapter,
                textOffset: textOffset,
                token: highlightNavigationToken
            )
            DebugLogger.info("[HighlightNav] navigateTo: 已设置 pendingHighlightNavigation, token=\(highlightNavigationToken), textOffset=\(textOffset)")
        } else {
            DebugLogger.warning("[HighlightNav] navigateTo: textOffset 为 nil，仅使用 pageIndex=\(location.pageIndex) 回退定位")
        }
    }

    private func handleCopySelectedText() {
        guard let info = selectedTextInfo else {
            showHint(NSLocalizedString("reader.copy.selection_required", comment: ""))
            return
        }
        UIPasteboard.general.string = info.text
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.success)
        showHint(NSLocalizedString("reader.copy.success", comment: ""))
    }

    private func handleCopyHighlightText(_ highlight: Highlight) {
        let resolvedText = activeHighlightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? highlight.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            : activeHighlightText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedText.isEmpty else {
            showHint(NSLocalizedString("reader.copy.selection_required", comment: ""))
            return
        }
        UIPasteboard.general.string = resolvedText
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.success)
        showHint(NSLocalizedString("reader.copy.success", comment: ""))
    }

    private func syncHighlightNoteDraftIfNeeded(force: Bool = false) {
        guard let highlight = activeHighlight else {
            noteDraftHighlightObjectID = nil
            highlightNoteDraft = ""
            return
        }
        guard force || noteDraftHighlightObjectID != highlight.objectID else { return }
        noteDraftHighlightObjectID = highlight.objectID
        highlightNoteDraft = highlight.note ?? ""
    }

    private func saveHighlightNoteDraftIfNeeded() {
        guard let highlight = activeHighlight else { return }
        let trimmedDraft = highlightNoteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedStored = highlight.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmedDraft != trimmedStored else { return }

        highlight.note = trimmedDraft.isEmpty ? nil : trimmedDraft
        highlight.updatedAt = Date()
        do {
            try viewContext.save()
        } catch {
            DebugLogger.error("ReaderView: 保存高亮笔记失败", error: error)
            showHint(NSLocalizedString("reader.highlight.save_failed", comment: ""))
        }
    }

    private func openHighlightNoteEditor() {
        syncHighlightNoteDraftIfNeeded(force: true)
        showingHighlightNoteEditor = true
    }

    private func submitHighlightCustomAIQuestion(for highlight: Highlight) {
        let question = highlightAIQuestionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            showHint(NSLocalizedString("reader.ai.question.empty", comment: ""))
            return
        }
        highlightAIQuestionDraft = ""
        showingHighlightAskComposer = false
        isHighlightQuestionFieldFocused = false
        isHighlightNoteEditorFocused = false
        saveHighlightNoteDraftIfNeeded()
        showingHighlightActions = false
        startAIRequest(.custom(question: question), sourceText: highlight.selectedText, targetHighlight: highlight)
    }

    private func openSelectionAskComposer() {
        guard let info = selectedTextInfo else {
            showHint(NSLocalizedString("reader.selection.required", comment: ""))
            return
        }
        let trimmed = info.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showHint(NSLocalizedString("reader.selection.required", comment: ""))
            return
        }
        pendingSelectionClearWorkItem?.cancel()
        selectionAskSourceText = trimmed
        customAIQuestionDraft = ""
        showingSelectionAskComposer = true
        scheduleSelectionQuestionFieldFocus()
    }

    private func dismissSelectionAskComposer(clearDraft: Bool = false) {
        isCustomQuestionFieldFocused = false
        showingSelectionAskComposer = false
        if clearDraft {
            customAIQuestionDraft = ""
        }
    }

    private func scheduleSelectionQuestionFieldFocus() {
        guard showingSelectionAskComposer else { return }
        DispatchQueue.main.async {
            guard showingSelectionAskComposer else { return }
            isCustomQuestionFieldFocused = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard showingSelectionAskComposer else { return }
            isCustomQuestionFieldFocused = true
        }
    }

    private func submitSelectionCustomAIQuestion() {
        let question = customAIQuestionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            showHint(NSLocalizedString("reader.ai.question.empty", comment: ""))
            return
        }
        let sourceText = selectionAskSourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else {
            showHint(NSLocalizedString("reader.ai.selection_required", comment: ""))
            return
        }
        customAIQuestionDraft = ""
        dismissSelectionAskComposer()
        startAIRequest(.custom(question: question), sourceText: sourceText)
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
            showHint(NSLocalizedString("reader.ai.selection_required", comment: ""))
            return
        }
        guard !isLoadingAIResponse else { return }

        let customQuestion: String?
        switch action {
        case .custom(let question):
            let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedQuestion.isEmpty else {
                showHint(NSLocalizedString("reader.ai.question.empty", comment: ""))
                return
            }
            customQuestion = trimmedQuestion
        default:
            customQuestion = nil
        }

        aiActionInFlight = action
        aiInsertionTarget = targetHighlight != nil ? .highlight(targetHighlight!) : (selectedTextInfo != nil ? .selection : nil)
        switch action {
        case .translate:
            aiResponseTitle = NSLocalizedString("reader.ai.translate", comment: "")
        case .explain:
            aiResponseTitle = NSLocalizedString("reader.ai.explain", comment: "")
        case .custom:
            aiResponseTitle = NSLocalizedString("reader.ai.ask", comment: "")
        }
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
                case .custom:
                    result = try await ReadingAIService.shared.ask(
                        question: customQuestion ?? "",
                        about: text,
                        locale: appSettings.language
                    )
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

    private func submitCustomAIQuestion() {
        submitSelectionCustomAIQuestion()
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
                showHint(NSLocalizedString("reader.highlight.save_failed", comment: ""))
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
            showHint(NSLocalizedString("reader.selection.required", comment: ""))
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
            showHint(NSLocalizedString("reader.highlight.failed", comment: ""))
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
            let action = ReaderSelectionAction(type: .highlight(colorHex: colorHex))
            selectionAction = action
            DispatchQueue.main.async {
                if self.selectionAction?.id == action.id {
                    self.selectionAction = nil
                }
            }
            let feedback = UINotificationFeedbackGenerator()
            feedback.notificationOccurred(.success)
            showHint(trimmedNote.isEmpty ? NSLocalizedString("reader.highlight.saved", comment: "") : NSLocalizedString("reader.highlight.saved_with_note", comment: ""))
            selectedTextInfo = nil
        } catch {
            DebugLogger.error("ReaderView: 保存高亮失败", error: error)
            showHint(NSLocalizedString("reader.highlight.save_failed", comment: ""))
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
                        Text(NSLocalizedString("reader.selection.title", comment: ""))
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
            .navigationTitle(NSLocalizedString("reader.note.add", comment: ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("common.cancel", comment: "")) {
                        showingNoteEditor = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("common.save", comment: "")) {
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
            ZStack {
                highlightActionSheetContent
                    .blur(radius: showingHighlightAskComposer ? 10 : 0)
                    .allowsHitTesting(!showingHighlightAskComposer)
                    .animation(.easeInOut(duration: 0.2), value: showingHighlightAskComposer)

                if showingHighlightAskComposer, let highlight = activeHighlight {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismissHighlightAskComposer()
                        }

                    GeometryReader { geometry in
                        highlightAskComposer(for: highlight, in: geometry)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle(NSLocalizedString("highlight.action.title", comment: ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if !showingHighlightNoteEditor {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(NSLocalizedString("common.close", comment: "")) {
                            dismissHighlightAskComposer(clearDraft: true)
                            isHighlightNoteEditorFocused = false
                            saveHighlightNoteDraftIfNeeded()
                            showingHighlightActions = false
                            activeHighlight = nil
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $showingHighlightNoteEditor) {
                highlightNoteEditorSheet
            }
        }
        .onAppear {
            syncHighlightNoteDraftIfNeeded()
        }
        .onChange(of: activeHighlight?.objectID) { _ in
            syncHighlightNoteDraftIfNeeded()
            if activeHighlight == nil {
                dismissHighlightAskComposer(clearDraft: true)
            }
        }
        .onDisappear {
            dismissHighlightAskComposer(clearDraft: true)
            isHighlightNoteEditorFocused = false
            saveHighlightNoteDraftIfNeeded()
            noteDraftHighlightObjectID = nil
        }
        .onChange(of: showingHighlightAskComposer) { isShowing in
            if isShowing {
                scheduleHighlightQuestionFieldFocus()
            }
        }
    }

    private var highlightActionSheetContent: some View {
        Group {
            if let highlight = activeHighlight {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
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
                            Button {
                                openHighlightNoteEditor()
                            } label: {
                                HStack(alignment: .center, spacing: 10) {
                                    let note = highlight.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                    Text(note.isEmpty ? NSLocalizedString("highlight.action.note_edit_placeholder", comment: "") : note)
                                        .font(.body)
                                        .foregroundColor(note.isEmpty ? .secondary : .primary)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Image(systemName: "square.and.pencil")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.secondary)
                                        .padding(.top, 2)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.05))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.primary.opacity(0.08))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 12) {
                        let columns = [
                            GridItem(.flexible(minimum: 120), spacing: 10),
                            GridItem(.flexible(minimum: 120), spacing: 10)
                        ]
                        LazyVGrid(columns: columns, spacing: 10) {
                            Button {
                                saveHighlightNoteDraftIfNeeded()
                                showingHighlightActions = false
                                startAIRequest(.explain, sourceText: highlight.selectedText, targetHighlight: highlight)
                            } label: {
                                Label(NSLocalizedString("reader.ai.explain", comment: ""), systemImage: "brain.head.profile")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(maxWidth: .infinity, minHeight: 40)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                saveHighlightNoteDraftIfNeeded()
                                showingHighlightActions = false
                                startAIRequest(.translate, sourceText: highlight.selectedText, targetHighlight: highlight)
                            } label: {
                                Label(NSLocalizedString("reader.ai.translate", comment: ""), systemImage: "globe")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(maxWidth: .infinity, minHeight: 40)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                handleCopyHighlightText(highlight)
                            } label: {
                                Label(NSLocalizedString("highlight.action.copy_highlight", comment: ""), systemImage: "doc.on.doc")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(maxWidth: .infinity, minHeight: 40)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                openHighlightAskComposer()
                            } label: {
                                Label(NSLocalizedString("reader.ai.ask", comment: ""), systemImage: "sparkles")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(maxWidth: .infinity, minHeight: 40)
                            }
                            .buttonStyle(.bordered)

                            if let note = highlight.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                                Button(role: .destructive) {
                                    isHighlightNoteEditorFocused = false
                                    saveHighlightNoteDraftIfNeeded()
                                    requestHighlightDeletion(highlight, noteOnly: true)
                                } label: {
                                    Label(NSLocalizedString("highlight.action.delete_note", comment: ""), systemImage: "trash")
                                        .font(.system(size: 15, weight: .semibold))
                                        .frame(maxWidth: .infinity, minHeight: 40)
                                }
                                .buttonStyle(.bordered)
                            }

                            Button(role: .destructive) {
                                isHighlightNoteEditorFocused = false
                                saveHighlightNoteDraftIfNeeded()
                                requestHighlightDeletion(highlight, noteOnly: false)
                            } label: {
                                Label(NSLocalizedString("highlight.action.delete_highlight", comment: ""), systemImage: "trash.slash")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(maxWidth: .infinity, minHeight: 40)
                            }
                            .buttonStyle(.bordered)
                        }

                        if appSettings.areAdsEnabled {
                            adBannerSection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .background(.ultraThinMaterial)
                    .overlay(alignment: .top) {
                        Divider()
                            .opacity(0.55)
                    }
                }
            } else {
                Text(NSLocalizedString("common.no_content", comment: ""))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
            }
        }
    }

    private func highlightAskComposer(for highlight: Highlight, in geometry: GeometryProxy) -> some View {
        let composerWidth = min(max(geometry.size.width - 16, 320), 820)
        let trimmedQuestion = highlightAIQuestionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let canSubmitQuestion = !trimmedQuestion.isEmpty && !isLoadingAIResponse
        let screenHeight = UIScreen.main.bounds.height
        let containerConsumedHeight = max(0, screenHeight - geometry.size.height)
        let keyboardAdditionalInset = max(0, keyboardHeight - containerConsumedHeight)
        let defaultBottomPadding = geometry.safeAreaInsets.bottom + 12
        let keyboardPinnedBottomPadding = max(defaultBottomPadding, keyboardAdditionalInset + 6)
        let resolvedText = activeHighlightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? highlight.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            : activeHighlightText.trimmingCharacters(in: .whitespacesAndNewlines)
        let panelChromeHeight: CGFloat = 124
        let availablePreviewSpace = max(
            96,
            geometry.size.height - geometry.safeAreaInsets.top - keyboardPinnedBottomPadding - panelChromeHeight
        )
        let previewMaxHeight = min(320, availablePreviewSpace)
        let previewMinHeight = min(140, previewMaxHeight)
        let previewLineLimit = max(4, Int((previewMaxHeight / 22).rounded(.down)))

        return VStack(spacing: 10) {
            selectionPreviewCard(
                text: resolvedText.isEmpty ? NSLocalizedString("common.no_content", comment: "") : resolvedText,
                maxHeight: previewMaxHeight,
                lineLimit: previewLineLimit,
                minHeight: previewMinHeight,
                title: NSLocalizedString("highlight.action.content", comment: "")
            )

            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.blue.opacity(0.9))
                    .frame(width: 24, height: 24)

                TextField(
                    NSLocalizedString("reader.ai.question.placeholder", comment: ""),
                    text: $highlightAIQuestionDraft
                )
                .textInputAutocapitalization(.sentences)
                .submitLabel(.send)
                .focused($isHighlightQuestionFieldFocused)
                .onSubmit {
                    submitHighlightCustomAIQuestion(for: highlight)
                }

                Button {
                    submitHighlightCustomAIQuestion(for: highlight)
                } label: {
                    ZStack {
                        Circle()
                            .fill(canSubmitQuestion ? Color.blue : Color.secondary.opacity(0.22))
                            .frame(width: 30, height: 30)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .disabled(!canSubmitQuestion)
                .accessibilityLabel(NSLocalizedString("reader.ai.question.send", comment: ""))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.68))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.primary.opacity(0.09))
        )
        .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 8)
        .frame(width: composerWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.horizontal, 8)
        .padding(.bottom, keyboardPinnedBottomPadding)
        .onAppear {
            scheduleHighlightQuestionFieldFocus()
        }
    }

    private func openHighlightAskComposer() {
        highlightAIQuestionDraft = ""
        isHighlightNoteEditorFocused = false
        isCustomQuestionFieldFocused = false
        showingHighlightAskComposer = true
        scheduleHighlightQuestionFieldFocus()
    }

    private func dismissHighlightAskComposer(clearDraft: Bool = false) {
        isHighlightQuestionFieldFocused = false
        showingHighlightAskComposer = false
        if clearDraft {
            highlightAIQuestionDraft = ""
        }
    }

    private func scheduleHighlightQuestionFieldFocus() {
        guard showingHighlightAskComposer else { return }
        DispatchQueue.main.async {
            guard showingHighlightAskComposer else { return }
            isHighlightQuestionFieldFocused = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard showingHighlightAskComposer else { return }
            isHighlightQuestionFieldFocused = true
        }
    }

    private var highlightNoteEditorSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let highlight = activeHighlight {
                Text(highlight.selectedText)
                    .font(.system(size: 15, design: .serif))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(10)
            }

            TextEditor(text: $highlightNoteDraft)
                .font(.body)
                .focused($isHighlightNoteEditorFocused)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08))
                )
        }
        .padding()
        .navigationTitle(NSLocalizedString("highlight.list.edit_note", comment: ""))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(NSLocalizedString("common.cancel", comment: "")) {
                    isHighlightNoteEditorFocused = false
                    syncHighlightNoteDraftIfNeeded(force: true)
                    showingHighlightNoteEditor = false
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(NSLocalizedString("common.save", comment: "")) {
                    isHighlightNoteEditorFocused = false
                    saveHighlightNoteDraftIfNeeded()
                    showingHighlightNoteEditor = false
                }
            }
        }
        .onAppear {
            syncHighlightNoteDraftIfNeeded(force: true)
            DispatchQueue.main.async {
                isHighlightNoteEditorFocused = true
            }
        }
        .onDisappear {
            isHighlightNoteEditorFocused = false
        }
    }

    private var aiResponseSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if isLoadingAIResponse {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text(NSLocalizedString("ai.generating", comment: ""))
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
                        Text(aiResponseContent.isEmpty ? NSLocalizedString("common.no_content", comment: "") : aiResponseContent)
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

                adBannerFooter
            }
            .padding()
            .navigationTitle(aiResponseTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("common.close", comment: "")) {
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
            showHint(NSLocalizedString("reader.highlight.save_failed", comment: ""))
        }

        pendingDeleteHighlight = nil
        deletingNoteOnly = false
    }

    private var adBannerSection: some View {
        Group {
            if appSettings.areAdsEnabled {
                if let adUnit = AdMobAdUnitIDs.fixedBanner {
                    BannerAdView(adUnitID: adUnit)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                } else {
                    Text(NSLocalizedString("ads.slot_not_configured", comment: ""))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(12)
                }
            }
        }
    }

    @ViewBuilder
    private var adBannerFooter: some View {
        if appSettings.areAdsEnabled {
            Spacer(minLength: 0)
            adBannerSection
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

    private func handleKeyboardFrameChange(_ notification: Notification) {
        let userInfo = notification.userInfo ?? [:]
        let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
        let curveValue = (userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.intValue ?? UIView.AnimationCurve.easeInOut.rawValue
        let keyboardFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? CGRect(
            x: 0,
            y: UIScreen.main.bounds.maxY,
            width: 0,
            height: 0
        )

        let screenBounds = UIScreen.main.bounds
        let overlap = max(0, screenBounds.maxY - keyboardFrame.minY)
        let animation = keyboardAnimation(duration: duration, curveValue: curveValue)

        withAnimation(animation) {
            keyboardHeight = overlap
        }
    }

    private func keyboardAnimation(duration: Double, curveValue: Int) -> Animation {
        let clampedDuration = max(0.12, duration)
        let curve = UIView.AnimationCurve(rawValue: curveValue) ?? .easeInOut

        switch curve {
        case .easeIn:
            return .easeIn(duration: clampedDuration)
        case .easeOut:
            return .easeOut(duration: clampedDuration)
        case .linear:
            return .linear(duration: clampedDuration)
        case .easeInOut:
            return .easeInOut(duration: clampedDuration)
        @unknown default:
            return .easeInOut(duration: clampedDuration)
        }
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
        bookmark.colorHex = Bookmark.defaultColorHex
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

                    // Historical data may contain chapter count in totalPages.
                    // Repair it with parser-estimated total pages when needed.
                    let minimumReasonableTotalPages = max(metadata.chapters.count, 1)
                    let parsedTotalPages = max(metadata.totalPages, minimumReasonableTotalPages)
                    if Int(self.book.totalPages) <= minimumReasonableTotalPages {
                        self.book.totalPages = Int32(min(parsedTotalPages, Int(Int32.max)))
                    }
                    
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

                    if !self.hasReportedInitialChapterOpenMetric {
                        self.reportChapterOpenMetric()
                    }
                    
                    self.isLoading = false
                    self.preloadNearbyChapterHTML(around: self.currentChapterIndex)
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
        let targetFragment = normalizeTOCFragment(location.tocFragment)
        ensurePageArrays()
        currentChapterIndex = targetChapter
        setChapterPageIndex(targetChapter, max(0, location.pageIndex))
        DebugLogger.info("ReaderView: 应用书签定位到章节 \(targetChapter + 1)，页码 \(safeChapterPageIndex(targetChapter) + 1)")

        currentTOCFragment = targetFragment
        if let targetFragment {
            tocNavigationToken += 1
            pendingTOCNavigation = TOCNavigationRequest(
                chapterIndex: targetChapter,
                fragment: targetFragment,
                token: tocNavigationToken
            )
            DebugLogger.info("ReaderView: 应用初始 TOC fragment=\(targetFragment), token=\(tocNavigationToken)")
        } else {
            pendingTOCNavigation = nil
        }

        if let textOffset = location.textOffset {
            highlightNavigationToken += 1
            pendingHighlightNavigation = HighlightNavigationRequest(
                chapterIndex: targetChapter,
                textOffset: textOffset,
                token: highlightNavigationToken
            )
            DebugLogger.info("[HighlightNav] applyInitialLocationIfAvailable: 已设置 pendingHighlightNavigation, token=\(highlightNavigationToken), textOffset=\(textOffset)")
        }

        return true
    }

    private func reportBookOpenMetric() {
        UsageMetricsReporter.shared.record(
            interface: UsageMetricsInterface.readerBookOpen,
            statusCode: 200,
            latencyMs: 0,
            requestBytes: 0,
            retryCount: 0,
            source: .reader
        )
    }

    private func reportChapterOpenMetric() {
        guard chapters.indices.contains(currentChapterIndex) else { return }
        UsageMetricsReporter.shared.record(
            interface: UsageMetricsInterface.readerChapterOpen,
            statusCode: 200,
            latencyMs: 0,
            requestBytes: 0,
            retryCount: 0,
            source: .reader
        )
        hasReportedInitialChapterOpenMetric = true
    }
    
    private func restoreReadingProgress() {
        guard let progress = book.readingProgress, !chapters.isEmpty else { return }
        ensurePageArrays()
        var restoredFromPosition = false

        if let positionJSON = progress.currentPosition,
           let data = positionJSON.data(using: .utf8),
           let positionData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let savedPageIndex = intValue(from: positionData["pageIndex"]) {

            if let savedChapterIndex = intValue(from: positionData["chapterIndex"]),
               savedChapterIndex >= 0 && savedChapterIndex < chapters.count {
                currentChapterIndex = savedChapterIndex
                setChapterPageIndex(savedChapterIndex, savedPageIndex)
            } else {
                currentChapterIndex = min(max(Int(progress.currentPage), 0), chapters.count - 1)
                setChapterPageIndex(currentChapterIndex, savedPageIndex)
            }
            restoredFromPosition = true
        }

        if !restoredFromPosition {
            // Legacy imports once initialized currentPage as 1 with 0% progress.
            let legacyChapterIndex = Int(progress.currentPage)
            let shouldResetToStart = progress.progressPercentage <= 0.0001 && legacyChapterIndex > 0
            let fallbackChapterIndex = shouldResetToStart ? 0 : legacyChapterIndex
            currentChapterIndex = min(max(fallbackChapterIndex, 0), chapters.count - 1)
            setChapterPageIndex(currentChapterIndex, 0)
            if shouldResetToStart {
                DebugLogger.info("ReaderView: 检测到旧版初始进度数据，已回退到第一章")
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
            progress.detailedReadingTime = 0
            progress.skimmingReadingTime = 0
            progress.book = book
            book.readingProgress = progress
        }
        
        if let progress = book.readingProgress {
            progress.currentPage = Int32(currentChapterIndex)

            let totalBookPages = resolvedBookTotalPages()
            let currentGlobalPage = currentGlobalPageNumber(totalBookPages: totalBookPages)
            
            // Save the current page within chapter to currentPosition as JSON
            let positionData: [String: Any] = [
                "chapterIndex": currentChapterIndex,
                "pageIndex": safeChapterPageIndex(currentChapterIndex),
                "totalPages": safeChapterTotalPages(currentChapterIndex),
                "globalPage": currentGlobalPage,
                "bookTotalPages": totalBookPages
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: positionData),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                progress.currentPosition = jsonString
            }
            
            // Calculate by absolute book page: current global page / total book pages
            progress.progressPercentage = min(1.0, Double(currentGlobalPage) / Double(max(totalBookPages, 1)))
            progress.lastReadAt = Date()
            progress.updatedAt = Date()
            
            // Update book's totalPages if needed
            let safeTotalBookPages = min(totalBookPages, Int(Int32.max))
            if book.totalPages != Int32(safeTotalBookPages) {
                book.totalPages = Int32(safeTotalBookPages)
            }
            
            // Update reading status based on progress
            if let libraryItem = book.libraryItem {
                // Update lastAccessedAt
                libraryItem.lastAccessedAt = Date()
                
                // If progress reaches 100%, mark as finished
                if isAtLastPageInBook() || progress.progressPercentage >= 0.99 {
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
#if DEBUG
                print("✅ Reading progress saved: Chapter \(currentChapterIndex), Page \(safeChapterPageIndex(currentChapterIndex)), GlobalPage \(currentGlobalPage)/\(totalBookPages), Progress: \(String(format: "%.1f%%", progress.progressPercentage * 100))")
#endif
            } catch {
#if DEBUG
                print("❌ Failed to save reading progress: \(error)")
#endif
            }
        }
    }
    
    // MARK: - Pagination helpers
    private func ensurePageArrays() {
        let targetCount = max(chapters.count, 1)
        if chapterPageIndices.count != targetCount {
            chapterPageIndices = resizedArray(chapterPageIndices, to: targetCount, fill: 0)
        }
        if chapterTotalPages.count != targetCount {
            chapterTotalPages = resizedArray(chapterTotalPages, to: targetCount, fill: 1)
        }
        if chapterPageCountsMeasured.count != targetCount {
            chapterPageCountsMeasured = resizedArray(chapterPageCountsMeasured, to: targetCount, fill: false)
        }
    }

    private func resizedArray<T>(_ source: [T], to targetCount: Int, fill: T) -> [T] {
        var resized = Array(repeating: fill, count: targetCount)
        let copyCount = min(source.count, targetCount)
        guard copyCount > 0 else { return resized }
        resized.replaceSubrange(0..<copyCount, with: source.prefix(copyCount))
        return resized
    }

    private func intValue(from any: Any?) -> Int? {
        if let value = any as? Int {
            return value
        }
        if let number = any as? NSNumber {
            return number.intValue
        }
        if let text = any as? String {
            return Int(text)
        }
        return nil
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
    
    private func storedChapterTotalPages(_ index: Int) -> Int {
        ensurePageArrays()
        guard index >= 0 && index < chapterTotalPages.count else { return 1 }
        return max(1, chapterTotalPages[index])
    }

    private func estimatedTotalPagesForUnmeasuredChapter(_ index: Int) -> Int {
        ensurePageArrays()
        guard index >= 0 && index < chapters.count else { return 1 }

        let chapterCount = max(chapters.count, 1)
        let fallbackTotalPages = max(Int(book.totalPages), chapterCount, 1)

        var measuredPages = 0
        var measuredCount = 0
        for chapterIndex in 0..<chapterCount where isChapterPageCountMeasured(chapterIndex) {
            measuredPages += storedChapterTotalPages(chapterIndex)
            measuredCount += 1
        }

        let remainingChapters = max(chapterCount - measuredCount, 1)
        let remainingPages = max(fallbackTotalPages - measuredPages, remainingChapters)
        let estimatedPerChapter = Int((Double(remainingPages) / Double(remainingChapters)).rounded())
        return max(1, estimatedPerChapter)
    }

    private func safeChapterTotalPages(_ index: Int) -> Int {
        ensurePageArrays()
        guard index >= 0 && index < chapterTotalPages.count else { return 1 }
        let storedTotal = storedChapterTotalPages(index)
        if isChapterPageCountMeasured(index) {
            return storedTotal
        }
        return max(storedTotal, estimatedTotalPagesForUnmeasuredChapter(index))
    }
    
    private func setChapterTotalPages(_ index: Int, _ value: Int) {
        ensurePageArrays()
        guard index >= 0 && index < chapterTotalPages.count else { return }
        chapterTotalPages[index] = max(1, value)
        chapterPageCountsMeasured[index] = true
        clampCurrentPage(index)
    }

    private func isChapterPageCountMeasured(_ index: Int) -> Bool {
        ensurePageArrays()
        guard index >= 0 && index < chapterPageCountsMeasured.count else { return false }
        return chapterPageCountsMeasured[index]
    }

    private func resolvedBookTotalPages() -> Int {
        ensurePageArrays()
        let chapterCount = max(chapters.count, 1)
        let fallbackTotalPages = max(Int(book.totalPages), 1)
        let fallbackPagesPerChapter = max(1, Int((Double(fallbackTotalPages) / Double(chapterCount)).rounded()))

        var measuredPages = 0
        var measuredCount = 0
        for index in 0..<chapterCount where isChapterPageCountMeasured(index) {
            measuredPages += safeChapterTotalPages(index)
            measuredCount += 1
        }

        if measuredCount == chapterCount {
            return max(measuredPages, 1)
        }

        let estimatedTotalPages = measuredPages + (chapterCount - measuredCount) * fallbackPagesPerChapter
        return max(fallbackTotalPages, estimatedTotalPages, 1)
    }

    private func currentGlobalPageNumber(totalBookPages: Int) -> Int {
        ensurePageArrays()
        let chapterCount = max(chapters.count, 1)
        let clampedChapterIndex = min(max(currentChapterIndex, 0), chapterCount - 1)
        let fallbackPagesPerChapter = max(1, Int((Double(totalBookPages) / Double(chapterCount)).rounded()))

        var pagesBeforeCurrentChapter = 0
        if clampedChapterIndex > 0 {
            for index in 0..<clampedChapterIndex {
                if isChapterPageCountMeasured(index) {
                    pagesBeforeCurrentChapter += safeChapterTotalPages(index)
                } else {
                    pagesBeforeCurrentChapter += fallbackPagesPerChapter
                }
            }
        }

        let currentPageInChapter = safeChapterPageIndex(clampedChapterIndex)
        let pageNumber = pagesBeforeCurrentChapter + currentPageInChapter + 1
        return max(1, min(totalBookPages, pageNumber))
    }

    private func isAtLastPageInBook() -> Bool {
        ensurePageArrays()
        guard !chapters.isEmpty else { return false }

        let clampedChapterIndex = min(max(currentChapterIndex, 0), chapters.count - 1)
        guard clampedChapterIndex == chapters.count - 1 else { return false }

        let totalPagesInChapter = safeChapterTotalPages(clampedChapterIndex)
        let currentPageInChapter = safeChapterPageIndex(clampedChapterIndex)
        return currentPageInChapter >= max(totalPagesInChapter - 1, 0)
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
    private func turnPage(
        _ direction: PageTurnDirection,
        source: PageTurnSource,
        clearSelection: Bool = true,
        allowWhenSelectionActive: Bool = false
    ) -> Bool {
        if selectedTextInfo != nil, !allowWhenSelectionActive {
            return false
        }
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

        if source == .tap && showingToolbar {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                showingToolbar = false
            }
        }
        
        saveReadingProgress()
        if clearSelection {
            selectedTextInfo = nil
        }
        provideTurnHaptic(for: source)
        return true
    }

    private func provideTurnHaptic(for source: PageTurnSource) {
        switch source {
        case .tap:
            let feedback = UIImpactFeedbackGenerator(style: .soft)
            feedback.impactOccurred(intensity: 0.35)
        case .swipe:
            let feedback = UIImpactFeedbackGenerator(style: .light)
            feedback.impactOccurred(intensity: 0.4)
        }
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
        syncLiveActivityReadingProgressIfNeeded(reason: "startReadingSession")
        
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
        syncLiveActivityReadingProgressIfNeeded(reason: "endReadingSession")
    }
    
    private func pauseReadingSession() {
        updateReadingTime()
        readingStartTime = nil
        isActivelyReading = false
        syncLiveActivityReadingProgressIfNeeded(reason: "pauseReadingSession")
    }
    
    private func resumeReadingSession() {
        readingStartTime = Date()
        isActivelyReading = true
        syncLiveActivityReadingProgressIfNeeded(reason: "resumeReadingSession")
    }
    
    private func updateReadingTime(resetStartTime: Bool = false) {
        guard let startTime = readingStartTime, isActivelyReading else { return }
        
        let now = Date()
        let timeElapsed = now.timeIntervalSince(startTime)
        
        // Only count if the reading session is meaningful (more than 1 second)
        guard timeElapsed > 1 else { return }
        let elapsedSeconds = Int(timeElapsed.rounded(.down))
        guard elapsedSeconds > 0 else { return }
        
        // Create or get reading progress
        if book.readingProgress == nil {
            let progress = ReadingProgress(context: viewContext)
            progress.id = UUID()
            progress.createdAt = Date()
            progress.updatedAt = Date()
            progress.totalReadingTime = 0
            progress.detailedReadingTime = 0
            progress.skimmingReadingTime = 0
            progress.book = book
            book.readingProgress = progress
        }
        
        if let progress = book.readingProgress {
            progress.migrateLegacyReadingTimeBucketsIfNeeded()

            // Add elapsed time to total
            progress.totalReadingTime += Int64(elapsedSeconds)
            progress.detailedReadingTime += Int64(elapsedSeconds)
            progress.updatedAt = Date()
            
            do {
                try viewContext.save()
                ReadingDailyStatsStore.shared.addReadingSeconds(elapsedSeconds)
                syncLiveActivityReadingProgressIfNeeded(reason: "updateReadingTime")
            } catch {
#if DEBUG
                print("Failed to save reading time: \(error)")
#endif
            }
        }

        if resetStartTime {
            readingStartTime = now
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

    private func startReadingHeartbeat() {
        readingHeartbeatTask?.cancel()
        readingHeartbeatTask = Task { @MainActor in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: readingHeartbeatIntervalNanoseconds)
                } catch {
                    return
                }
                guard isActivelyReading else { continue }
                updateReadingTime(resetStartTime: true)
            }
        }
    }

    private func stopReadingHeartbeat() {
        readingHeartbeatTask?.cancel()
        readingHeartbeatTask = nil
    }

    private func syncLiveActivityReadingProgressIfNeeded(reason: String) {
        let minutesReadToday = currentLiveActivityMinutesReadToday()
        guard minutesReadToday != lastPublishedLiveActivityMinute else {
            return
        }
        lastPublishedLiveActivityMinute = minutesReadToday
        DebugLogger.info(
            "[LiveActivityFlow] Syncing Live Activity reading progress from ReaderView. " +
            "reason=\(reason), minutesReadToday=\(minutesReadToday), goalMinutes=\(appSettings.dailyReadingGoal)"
        )
        Task {
            await ReadingLiveActivityManager.shared.updateIfNeeded(
                goalMinutes: appSettings.dailyReadingGoal,
                minutesReadToday: minutesReadToday,
                deepLink: ReadingReminderConstants.defaultDeepLink
            )
        }
    }

    private func currentLiveActivityMinutesReadToday() -> Int {
        var totalSeconds = ReadingDailyStatsStore.shared.todayReadingSeconds()
        if let startTime = readingStartTime, isActivelyReading {
            let inFlightSeconds = Int(Date().timeIntervalSince(startTime).rounded(.down))
            if inFlightSeconds > 0 {
                totalSeconds += inFlightSeconds
            }
        }
        return max(0, totalSeconds / 60)
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
        if let lastSelectionInteractionTime,
           Date().timeIntervalSince(lastSelectionInteractionTime) < 0.45 {
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
        if let lastSelectionInteractionTime,
           Date().timeIntervalSince(lastSelectionInteractionTime) < 0.18 {
            return
        }
        guard !isAnimatingPageTurn else { return }
        pendingTapWorkItem?.cancel()

        let translation = value.translation
        let startLocation = value.startLocation

        if abs(translation.width) > abs(translation.height) && abs(translation.width) > 8 {
            if !isDragging {
                isDragging = true
                dragStartLocation = startLocation

                if showingToolbar {
                    withAnimation(.easeOut(duration: 0.15)) {
                        showingToolbar = false
                    }
                }
            }

            let maxOffset = geometry.size.width * 0.4
            let rawOffset = translation.width * 0.65

            let canGoNext = canNavigateToNextPage()
            let canGoPrevious = canNavigateToPreviousPage()

            if rawOffset > 0 && !canGoPrevious {
                let rubberBand = rubberBandClamp(rawOffset, limit: 60)
                dragOffset = rubberBand
            } else if rawOffset < 0 && !canGoNext {
                let rubberBand = rubberBandClamp(rawOffset, limit: 60)
                dragOffset = rubberBand
            } else {
                dragOffset = max(-maxOffset, min(maxOffset, rawOffset))
            }
        }
    }

    private func rubberBandClamp(_ offset: CGFloat, limit: CGFloat) -> CGFloat {
        let absOffset = abs(offset)
        let sign: CGFloat = offset >= 0 ? 1.0 : -1.0
        let damped = limit * (1 - exp(-absOffset / limit))
        return sign * damped
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

        guard selectedTextInfo == nil else {
            animateBackToOriginalPosition()
            isDragging = false
            return
        }

        let translation = value.translation
        let velocity = CGPoint(
            x: value.predictedEndTranslation.width - value.translation.width,
            y: value.predictedEndTranslation.height - value.translation.height
        )

        let threshold = geometry.size.width * 0.12
        let velocityThreshold: CGFloat = 150

        let shouldTurnPage = abs(translation.width) > threshold || abs(velocity.x) > velocityThreshold

        if shouldTurnPage && abs(translation.width) > abs(translation.height) {
            if translation.width > 0 && canNavigateToPreviousPage() {
                performPageTurn(direction: .previous)
            } else if translation.width < 0 && canNavigateToNextPage() {
                performPageTurn(direction: .next)
            } else {
                animateBackToOriginalPosition()
            }
        } else {
            animateBackToOriginalPosition()
        }

        isDragging = false
    }
    
    private func performPageTurn(direction: PageTurnDirection) {
        guard !isAnimatingPageTurn else { return }
        if let lastSwipeTurnTime,
           Date().timeIntervalSince(lastSwipeTurnTime) < 0.36 {
            animateBackToOriginalPosition()
            return
        }

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

        lastSwipeTurnTime = Date()
        isAnimatingPageTurn = true

        withAnimation(.spring(response: 0.28, dampingFraction: 0.92, blendDuration: 0)) {
            dragOffset = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            self.isAnimatingPageTurn = false
        }
    }

    private func animateBackToOriginalPosition() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
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
    
    // MARK: - Swipe visual feedback (Apple Books-style page edge shadow)

    private func slideVisualFeedback(geometry: GeometryProxy) -> some View {
        pageEdgeShadow(geometry: geometry)
            .allowsHitTesting(false)
    }

    private func pageEdgeShadow(geometry: GeometryProxy) -> some View {
        let progress = min(abs(dragOffset) / 100.0, 1.0)
        return ZStack {
            if dragOffset > 0 {
                HStack(spacing: 0) {
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.black.opacity(0.06 * progress), location: 0),
                            .init(color: Color.black.opacity(0.02 * progress), location: 0.4),
                            .init(color: .clear, location: 1)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 16)
                    Spacer()
                }
            } else {
                HStack(spacing: 0) {
                    Spacer()
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: Color.black.opacity(0.02 * progress), location: 0.6),
                            .init(color: Color.black.opacity(0.06 * progress), location: 1)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 16)
                }
            }
        }
    }
}

private struct SelectionAnchor: Codable {
    let chapterIndex: Int
    let pageIndex: Int
    let offset: Int
}

private struct TOCNavigationRequest: Equatable {
    let chapterIndex: Int
    let fragment: String?
    let token: Int
}

private struct SelectionToolbarHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct HighlightNavigationRequest: Equatable {
    let chapterIndex: Int
    let textOffset: Int
    let token: Int
}

struct TableOfContentsView: View {
    let tocItems: [TOCItem]
    let chapters: [Chapter]
    @Binding var currentChapterIndex: Int
    @Binding var currentTOCFragment: String?
    var onSelectTOCItem: ((Int, String?) -> Void)?
    @Environment(\.dismiss) private var dismiss
    
    private struct DisplayItem: Identifiable {
        let id: Int
        let title: String
        let chapterIndex: Int
        let level: Int
        let fragment: String?
    }

    private func normalizedFragment(_ fragment: String?) -> String? {
        guard let fragment else { return nil }
        let cleaned = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return cleaned.hasPrefix("#") ? String(cleaned.dropFirst()) : cleaned
    }
    
    private var displayItems: [DisplayItem] {
        if !tocItems.isEmpty {
            return tocItems.enumerated().map { index, item in
                DisplayItem(
                    id: index,
                    title: item.title,
                    chapterIndex: item.chapterIndex,
                    level: item.level,
                    fragment: item.fragment
                )
            }
        }
        
        return chapters.enumerated().map { index, chapter in
            DisplayItem(id: index, title: chapter.title, chapterIndex: index, level: 0, fragment: nil)
        }
    }

    private var primaryItemIDByChapter: [Int: Int] {
        var preferred: [Int: Int] = [:]
        var fallback: [Int: Int] = [:]

        for item in displayItems {
            if fallback[item.chapterIndex] == nil {
                fallback[item.chapterIndex] = item.id
            }
            if preferred[item.chapterIndex] == nil, normalizedFragment(item.fragment) == nil {
                preferred[item.chapterIndex] = item.id
            }
        }

        for (chapterIndex, fallbackID) in fallback where preferred[chapterIndex] == nil {
            preferred[chapterIndex] = fallbackID
        }

        return preferred
    }

    private var currentDisplayItemID: Int? {
        if let activeFragment = normalizedFragment(currentTOCFragment) {
            if let matchedID = displayItems.first(where: {
                $0.chapterIndex == currentChapterIndex &&
                normalizedFragment($0.fragment) == activeFragment
            })?.id {
                return matchedID
            }
        }
        return primaryItemIDByChapter[currentChapterIndex]
    }

    private func isCurrent(_ item: DisplayItem) -> Bool {
        item.id == currentDisplayItemID
    }
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(displayItems) { item in
                        Button(action: {
                            let fragment = normalizedFragment(item.fragment)
                            if let onSelectTOCItem {
                                onSelectTOCItem(item.chapterIndex, fragment)
                            } else {
                                currentChapterIndex = item.chapterIndex
                                currentTOCFragment = fragment
                            }
                            dismiss()
                        }) {
                            HStack(spacing: 12) {
                                // Chapter number indicator
                                ZStack {
                                    Circle()
                                        .fill(isCurrent(item) ?
                                              LinearGradient(gradient: Gradient(colors: [.blue, .blue.opacity(0.7)]), 
                                                           startPoint: .topLeading, 
                                                           endPoint: .bottomTrailing) :
                                              LinearGradient(gradient: Gradient(colors: [.gray.opacity(0.2), .gray.opacity(0.1)]), 
                                                           startPoint: .topLeading, 
                                                           endPoint: .bottomTrailing))
                                        .frame(width: 36, height: 36)
                                    
                                    Text("\(item.id + 1)")
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundColor(isCurrent(item) ? .white : .secondary)
                                }
                                
                                // Chapter title
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.system(size: 16, weight: .medium, design: .serif))
                                        .foregroundColor(.primary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    
                                    if isCurrent(item) {
                                        Text(NSLocalizedString("reader.current_chapter", comment: ""))
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundColor(.blue)
                                    }
                                }
                                
                                Spacer()
                                
                                if isCurrent(item) {
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
            .navigationTitle(NSLocalizedString("reader.toc.title", comment: ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Text(NSLocalizedString("common.done", comment: ""))
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.medium)
                    }
                }
            }
        }
    }
    
    private func scrollToCurrent(in proxy: ScrollViewProxy) {
        guard let targetID = currentDisplayItemID else { return }
        withAnimation {
            proxy.scrollTo(targetID, anchor: .center)
        }
    }
}

struct ReaderSettingsView: View {
    @StateObject private var appSettings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section(NSLocalizedString("settings.font.title", comment: "")) {
                    HStack {
                        Text(NSLocalizedString("settings.font.size", comment: ""))
                        Spacer()
                        Picker(NSLocalizedString("settings.font.size", comment: ""), selection: $appSettings.readingFontSize) {
                            ForEach(ReadingFontSize.allCases, id: \.rawValue) { size in
                                Text(size.displayName).tag(size)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                }
                
                Section(NSLocalizedString("settings.typography.title", comment: "")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(NSLocalizedString("settings.typography.line_spacing", comment: ""))
                            Spacer()
                            Text(String(format: "%.1f", appSettings.lineSpacing))
                                .foregroundColor(.secondary)
                        }
                        
                        Slider(
                            value: $appSettings.lineSpacing,
                            in: AppSettings.lineSpacingRange,
                            step: AppSettings.lineSpacingStep
                        )
                            .accentColor(.blue)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(NSLocalizedString("settings.typography.page_margins", comment: ""))
                            Spacer()
                            Text("\(Int(appSettings.pageMargins))pt")
                                .foregroundColor(.secondary)
                        }
                        
                        Slider(
                            value: $appSettings.pageMargins,
                            in: AppSettings.pageMarginsRange,
                            step: AppSettings.pageMarginsStep
                        )
                            .accentColor(.blue)
                    }
                }
                
                Section(NSLocalizedString("settings.theme.title", comment: "")) {
                    Picker(NSLocalizedString("settings.theme.title", comment: ""), selection: $appSettings.theme) {
                        ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
            }
            .navigationTitle(NSLocalizedString("reading.settings.title", comment: ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Text(NSLocalizedString("common.done", comment: ""))
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.medium)
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { dismiss() }) {
                        Text(NSLocalizedString("common.done", comment: ""))
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
