//
//  ReaderView.swift
//  Isla Reader
//
//  Created by 郭亮 on 2025/9/10.
//

import SwiftUI
import CoreData

struct ReaderView: View {
    let book: Book
    private let initialLocation: BookmarkLocation?
    
    @FetchRequest private var bookmarks: FetchedResults<Bookmark>
    @StateObject private var appSettings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    init(book: Book, initialLocation: BookmarkLocation? = nil) {
        self.book = book
        self.initialLocation = initialLocation
        _bookmarks = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Bookmark.createdAt, ascending: false)],
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
    @State private var selectedText = ""
    @State private var showingTextActions = false
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
        .sheet(isPresented: $showingTextActions) {
            TextActionsView(selectedText: selectedText)
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
        }
        .onChange(of: scenePhase) { newPhase in
            handleScenePhaseChange(newPhase)
        }
        .onChange(of: currentChapterIndex) { _ in
            // Save progress when chapter changes
            saveReadingProgress()
        }
    }
    
    // MARK: - View Components
    
    private var backgroundView: some View {
        Group {
            if appSettings.theme == .dark {
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
                isDarkMode: appSettings.theme == .dark,
                currentPageIndex: Binding(
                    get: { safeChapterPageIndex(index) },
                    set: { newValue in setChapterPageIndex(index, newValue) }
                ),
                totalPages: Binding(
                    get: { safeChapterTotalPages(index) },
                    set: { newValue in setChapterTotalPages(index, newValue) }
                ),
                onToolbarToggle: {
                    handleTap()
                },
                onTextSelected: { text in
                    selectedText = text
                    showingTextActions = true
                }
            )
            .frame(width: geometry.size.width, height: webViewHeight)
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
            
            // Tap zones: left/right for prev/next page
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(width: geometry.size.width * 0.28)
                    .onTapGesture { 
                        if !isDragging && !isAnimatingPageTurn {
                            previousPageOrChapter() 
                        }
                    }
                
                // Center tap zone to toggle toolbar/menu
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { 
                        if !isDragging && !isAnimatingPageTurn {
                            handleTap() 
                        }
                    }
                
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(width: geometry.size.width * 0.28)
                    .onTapGesture { 
                        if !isDragging && !isAnimatingPageTurn {
                            nextPageOrChapter() 
                        }
                    }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .offset(x: dragOffset)
            .gesture(
                DragGesture(minimumDistance: 10, coordinateSpace: .local)
                    .onChanged { value in
                        handleDragChanged(value, geometry: geometry)
                    }
                    .onEnded { value in
                        handleDragEnded(value, geometry: geometry)
                    }
            )
            
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
                toolbarButton(icon: "highlighter", action: { showingTextActions = true })
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
    
    private func nextPageOrChapter() {
        ensurePageArrays()
        let total = safeChapterTotalPages(currentChapterIndex)
        let page = safeChapterPageIndex(currentChapterIndex)
        if page < total - 1 {
            setChapterPageIndex(currentChapterIndex, page + 1)
        } else if currentChapterIndex < chapters.count - 1 {
            currentChapterIndex += 1
            setChapterPageIndex(currentChapterIndex, 0)
        }
        saveReadingProgress()
    }
    
    private func previousPageOrChapter() {
        ensurePageArrays()
        let page = safeChapterPageIndex(currentChapterIndex)
        if page > 0 {
            setChapterPageIndex(currentChapterIndex, page - 1)
        } else if currentChapterIndex > 0 {
            currentChapterIndex -= 1
            let lastPage = safeChapterTotalPages(currentChapterIndex) - 1
            setChapterPageIndex(currentChapterIndex, max(0, lastPage))
        }
        saveReadingProgress()
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
    
    private func handleDragChanged(_ value: DragGesture.Value, geometry: GeometryProxy) {
        // 防止在动画过程中处理新的拖拽
        guard !isAnimatingPageTurn else { return }
        
        let translation = value.translation
        let startLocation = value.startLocation
        
        // 检查是否是水平滑动（水平移动距离大于垂直移动距离）
        if abs(translation.width) > abs(translation.height) && abs(translation.width) > 10 {
            if !isDragging {
                isDragging = true
                dragStartLocation = startLocation
                // 轻微触觉反馈表示开始滑动
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                
                // 隐藏工具栏以获得更好的滑动体验
                if showingToolbar {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showingToolbar = false
                    }
                }
            }
            
            // 计算拖拽偏移，添加阻尼效果
            let maxOffset = geometry.size.width * 0.3 // 最大偏移为屏幕宽度的30%
            let dampingFactor: CGFloat = 0.6
            let rawOffset = translation.width * dampingFactor
            
            // 检查是否可以翻页
            let canGoNext = canNavigateToNextPage()
            let canGoPrevious = canNavigateToPreviousPage()
            
            if rawOffset > 0 && !canGoPrevious {
                // 向右滑动但无法向前翻页，减少阻力
                dragOffset = min(rawOffset * 0.3, maxOffset * 0.3)
            } else if rawOffset < 0 && !canGoNext {
                // 向左滑动但无法向后翻页，减少阻力
                dragOffset = max(rawOffset * 0.3, -maxOffset * 0.3)
            } else {
                // 正常滑动
                dragOffset = max(-maxOffset, min(maxOffset, rawOffset))
            }
            
            // 当达到翻页阈值时提供触觉反馈
            let threshold = geometry.size.width * 0.25
            if abs(dragOffset) > threshold * 0.8 && abs(translation.width) > threshold * 0.8 {
                // 只在第一次达到阈值时触发反馈
                let currentTime = Date().timeIntervalSince1970
                if currentTime - lastTapTime.timeIntervalSince1970 > 0.3 {
                    let selectionFeedback = UISelectionFeedbackGenerator()
                    selectionFeedback.selectionChanged()
                    lastTapTime = Date()
                }
            }
        }
    }
    
    private func handleDragEnded(_ value: DragGesture.Value, geometry: GeometryProxy) {
        guard isDragging else { return }
        
        let translation = value.translation
        let velocity = CGPoint(
            x: value.predictedEndTranslation.width - value.translation.width,
            y: value.predictedEndTranslation.height - value.translation.height
        )
        
        // 判断翻页阈值
        let threshold = geometry.size.width * 0.25 // 25%的屏幕宽度
        let velocityThreshold: CGFloat = 300 // 速度阈值
        
        let shouldTurnPage = abs(translation.width) > threshold || abs(velocity.x) > velocityThreshold
        
        if shouldTurnPage && abs(translation.width) > abs(translation.height) {
            if translation.width > 0 && canNavigateToPreviousPage() {
                // 向右滑动，翻到上一页
                performPageTurn(direction: .previous, geometry: geometry)
            } else if translation.width < 0 && canNavigateToNextPage() {
                // 向左滑动，翻到下一页
                performPageTurn(direction: .next, geometry: geometry)
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
    
    private func performPageTurn(direction: PageTurnDirection, geometry: GeometryProxy) {
        guard !isAnimatingPageTurn else { return }
        
        isAnimatingPageTurn = true
        
        // 成功翻页的触觉反馈
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        // 立即执行翻页逻辑
        switch direction {
        case .next:
            nextPageOrChapter()
        case .previous:
            previousPageOrChapter()
        }
        
        // 计算最终偏移位置
        let finalOffset: CGFloat = direction == .next ? -geometry.size.width : geometry.size.width
        
        // 执行翻页动画
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0)) {
            dragOffset = finalOffset
        }
        
        // 动画完成后重置状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.dragOffset = 0
            self.isAnimatingPageTurn = false
        }
    }
    
    private func animateBackToOriginalPosition() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
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
    
    private enum PageTurnDirection {
        case next
        case previous
    }
    
    // MARK: - 滑动视觉反馈
    
    private func slideVisualFeedback(geometry: GeometryProxy) -> some View {
        ZStack {
            // 滑动方向指示器
            if abs(dragOffset) > 20 {
                VStack {
                    Spacer()
                    
                    HStack {
                        if dragOffset > 0 {
                            // 向右滑动 - 上一页指示器
                            slideIndicator(
                                direction: .previous,
                                progress: min(abs(dragOffset) / (geometry.size.width * 0.25), 1.0),
                                canNavigate: canNavigateToPreviousPage()
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .opacity
                            ))
                            
                            Spacer()
                        } else {
                            // 向左滑动 - 下一页指示器
                            Spacer()
                            
                            slideIndicator(
                                direction: .next,
                                progress: min(abs(dragOffset) / (geometry.size.width * 0.25), 1.0),
                                canNavigate: canNavigateToNextPage()
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .opacity
                            ))
                        }
                    }
                    .padding(.horizontal, 40)
                    
                    Spacer()
                }
            }
            
            // 边缘发光效果
            if abs(dragOffset) > 10 {
                edgeGlowEffect(geometry: geometry)
            }
        }
        .allowsHitTesting(false)
    }
    
    private func slideIndicator(direction: PageTurnDirection, progress: CGFloat, canNavigate: Bool) -> some View {
        VStack(spacing: 8) {
            // 箭头图标
            Image(systemName: direction == .next ? "chevron.right" : "chevron.left")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(canNavigate ? .primary : .secondary)
                .scaleEffect(0.8 + progress * 0.4)
                .opacity(0.6 + progress * 0.4)
            
            // 进度指示器
            RoundedRectangle(cornerRadius: 2)
                .fill(canNavigate ? Color.blue : Color.secondary)
                .frame(width: 40, height: 4)
                .scaleEffect(x: progress, y: 1.0, anchor: .center)
                .opacity(0.7)
            
            // 提示文本
            Text(direction == .next ? "下一页" : "上一页")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(canNavigate ? .primary : .secondary)
                .opacity(progress > 0.5 ? 0.8 : 0.0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .opacity(0.8 + progress * 0.2)
        )
        .scaleEffect(0.9 + progress * 0.1)
    }
    
    private func edgeGlowEffect(geometry: GeometryProxy) -> some View {
        HStack {
            if dragOffset > 0 {
                // 左边缘发光
                LinearGradient(
                    gradient: Gradient(colors: [
                        canNavigateToPreviousPage() ? Color.blue.opacity(0.3) : Color.red.opacity(0.2),
                        Color.clear
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 8)
                .opacity(min(abs(dragOffset) / CGFloat(100), 1.0))
                
                Spacer()
            } else {
                Spacer()
                
                // 右边缘发光
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        canNavigateToNextPage() ? Color.blue.opacity(0.3) : Color.red.opacity(0.2)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 8)
                .opacity(min(abs(dragOffset) / CGFloat(100), 1.0))
            }
        }
    }
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
        NavigationView {
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
        NavigationView {
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

struct TextActionsView: View {
    let selectedText: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text(NSLocalizedString("选中文本", comment: ""))
                    .font(.headline)
                    .padding()
                    .background(.gray.opacity(0.1))
                    .cornerRadius(8)
                
                VStack(spacing: 16) {
                    ActionButton(title: NSLocalizedString("高亮标记", comment: ""), icon: "highlighter", color: .yellow) {}
                    ActionButton(title: NSLocalizedString("添加笔记", comment: ""), icon: "note.text", color: .blue) {}
                    ActionButton(title: NSLocalizedString("翻译", comment: ""), icon: "globe", color: .green) {}
                    ActionButton(title: NSLocalizedString("AI 解释", comment: ""), icon: "brain.head.profile", color: .purple) {}
                    ActionButton(title: NSLocalizedString("复制", comment: ""), icon: "doc.on.doc", color: .gray) {}
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle(NSLocalizedString("文本操作", comment: ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("完成", comment: "")) {
                        dismiss()
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    Button(NSLocalizedString("完成", comment: "")) {
                        dismiss()
                    }
                }
                #endif
            }
        }
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .frame(width: 24)
                
                Text(title)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(.gray.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
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
