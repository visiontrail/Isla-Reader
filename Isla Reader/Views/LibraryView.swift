//
//  LibraryView.swift
//  LanRead
//
//  Created by 郭亮 on 2025/9/10.
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers
import UIKit

// Filter type enum supporting both reading status and favorites
enum LibraryFilterType: Equatable {
    case all
    case favorites
    case status(ReadingStatus)
    
    var displayName: String {
        switch self {
        case .all:
            return NSLocalizedString("common.all", comment: "")
        case .favorites:
            return NSLocalizedString("library.favorite.title", comment: "")
        case .status(let status):
            return status.displayName
        }
    }
    
    var displayNameKey: LocalizedStringKey {
        switch self {
        case .all:
            return LocalizedStringKey("common.all")
        case .favorites:
            return LocalizedStringKey("library.favorite.title")
        case .status(let status):
            return status.displayNameKey
        }
    }
}

struct LibraryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var summaryService = AISummaryService.shared
    @StateObject private var importService = BookImportService.shared
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \LibraryItem.lastAccessedAt, ascending: false)],
        animation: .default)
    private var libraryItems: FetchedResults<LibraryItem>
    
    // 强制刷新视图的状态
    @State private var refreshID = UUID()
    
    @State private var searchText = ""
    @State private var selectedFilter: LibraryFilterType = .all
    @State private var showingImportSheet = false
    @State private var showingFilterSheet = false
    @State private var bookToShowAISummary: Book? = nil
    @State private var bookForSkimming: Book? = nil
    @State private var bookForBookmarks: Book? = nil
    @State private var bookForHighlights: Book? = nil
    @State private var libraryItemForInfo: LibraryItem? = nil
    @State private var readerLaunchTarget: ReaderLaunchTarget? = nil
    @State private var pendingLibraryRemoval: PendingLibraryRemoval? = nil
    @State private var activeAlert: LibraryAlert? = nil
    
    private var filteredBooks: [LibraryItem] {
        var items = Array(libraryItems).filter { !$0.isDeleted }
        
        // Apply search filter
        if !searchText.isEmpty {
            items = items.filter { item in
                item.book.title.localizedCaseInsensitiveContains(searchText) ||
                (item.book.author?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        // Apply filter type
        switch selectedFilter {
        case .all:
            break
        case .favorites:
            items = items.filter { $0.isFavorite }
        case .status(let status):
            items = items.filter { $0.status == status }
        }
        
        return items
    }
    
    private var columns: [GridItem] {
        let count = ResponsiveLayout.columns(for: horizontalSizeClass)
        let spacing = ResponsiveLayout.spacing(for: horizontalSizeClass)
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search and Filter Bar
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField(NSLocalizedString("library.search.placeholder", comment: ""), text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    
                    Button(action: { showingFilterSheet = true }) {
                        Image(systemName: selectedFilter != .all ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                // Content
                if filteredBooks.isEmpty {
                    EmptyLibraryView(onImportTap: handleAddBookTapped)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(filteredBooks, id: \.objectID) { item in
                                BookCardView(libraryItem: item, onTap: {
                                    withResolvedBook(from: item, actionName: "书籍卡片点击") { book in
                                        DebugLogger.info("LibraryView: 书籍卡片点击")
                                        DebugLogger.info("LibraryView: 点击的书籍 = \(book.displayTitle)")
                                        presentAISummary(for: book, source: "library_card_tap")
                                        DebugLogger.info("LibraryView: 已触发 AI 摘要展示")
                                    }
                                }, onSkim: {
                                    withResolvedBook(from: item, actionName: "进入略读模式") { book in
                                        DebugLogger.info("LibraryView: 进入略读模式 - \(book.displayTitle)")
                                        bookForSkimming = book
                                    }
                                }, onShowBookmarks: {
                                    withResolvedBook(from: item, actionName: "查看书签") { book in
                                        DebugLogger.info("LibraryView: 查看书签 - \(book.displayTitle)")
                                        bookForBookmarks = book
                                    }
                                }, onShowHighlights: {
                                    withResolvedBook(from: item, actionName: "查看高亮与笔记") { book in
                                        DebugLogger.info("LibraryView: 查看高亮与笔记 - \(book.displayTitle)")
                                        bookForHighlights = book
                                    }
                                }, onShowInfo: {
                                    guard let libraryItem = resolveLibraryItem(by: item.objectID) else {
                                        DebugLogger.warning("LibraryView: 查看书籍信息失败，LibraryItem 已失效，刷新列表")
                                        refreshData()
                                        return
                                    }
                                    DebugLogger.info("LibraryView: 查看书籍信息 - \(libraryItem.book.displayTitle)")
                                    libraryItemForInfo = libraryItem
                                }, onContinueReading: {
                                    withResolvedBook(from: item, actionName: "继续阅读") { book in
                                        continueReading(book)
                                    }
                                }, onToggleFavorite: {
                                    toggleFavorite(for: item)
                                }, onRemoveFromLibrary: {
                                    let title = resolveBook(from: item, actionName: "准备移除书籍")?.displayTitle
                                        ?? NSLocalizedString("book.info.unknown", comment: "")
                                    pendingLibraryRemoval = PendingLibraryRemoval(
                                        id: item.objectID,
                                        title: title
                                    )
                                })
                            }
                        }
                        .padding()
                        .id(refreshID)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("library.title", comment: ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: handleAddBookTapped) {
                        Image(systemName: "plus")
                            .font(.title2)
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    Button(action: handleAddBookTapped) {
                        Image(systemName: "plus")
                            .font(.title2)
                    }
                }
                #endif
            }
            .sheet(isPresented: $showingImportSheet) {
                ImportBookView(onBookImported: { book in
                    // 导入成功后，等待sheet关闭后再打开AI摘要
                    DebugLogger.info("LibraryView: onBookImported 回调触发")
                    DebugLogger.info("LibraryView: 导入的书籍 = \(book.displayTitle)")
                    // 等待ImportSheet完全关闭后再设置book，这会自动触发AI摘要sheet
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        DebugLogger.info("LibraryView: 延迟后打开AI摘要")
                        presentAISummary(for: book, source: "import_completion")
                        DebugLogger.info("LibraryView: 已设置 bookToShowAISummary = \(book.displayTitle)")
                    }
                })
            }
            .sheet(isPresented: $showingFilterSheet) {
                FilterSheetView(selectedFilter: $selectedFilter)
            }
            .fullScreenCover(item: $bookToShowAISummary) { book in
                NavigationStack {
                    AISummaryView(book: book)
                        .navigationTitle(book.displayTitle)
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button(action: {
                                    DebugLogger.info("LibraryView: 关闭按钮点击，关闭AI摘要界面")
                                    bookToShowAISummary = nil
                                    // 关闭时刷新数据
                                    refreshData()
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                }
                .environment(\.managedObjectContext, viewContext)
                .onAppear {
                    DebugLogger.info("LibraryView: AI摘要全屏界面正在显示")
                    DebugLogger.info("LibraryView: 选中的书籍 = \(book.displayTitle)")
                }
            }
            .fullScreenCover(item: $bookForSkimming) { book in
                NavigationStack {
                    SkimmingModeView(book: book)
                        .navigationBarHidden(true)
                }
                .onAppear {
                    DebugLogger.info("LibraryView: 略读模式界面显示 - \(book.displayTitle)")
                }
            }
            .sheet(item: $bookForBookmarks) { book in
                BookmarkListSheet(book: book) { location in
                    readerLaunchTarget = ReaderLaunchTarget(book: book, location: location)
                }
                .environment(\.managedObjectContext, viewContext)
            }
            .fullScreenCover(item: $bookForHighlights) { book in
                HighlightListSheet(book: book) { location in
                    readerLaunchTarget = ReaderLaunchTarget(book: book, location: location)
                }
                    .environment(\.managedObjectContext, viewContext)
            }
            .sheet(item: $libraryItemForInfo) { libraryItem in
                BookInfoSheet(libraryItem: libraryItem)
                    .environment(\.managedObjectContext, viewContext)
            }
            .confirmationDialog(
                NSLocalizedString("library.remove.confirm.title", comment: ""),
                isPresented: Binding(
                    get: { pendingLibraryRemoval != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingLibraryRemoval = nil
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                Button(NSLocalizedString("library.remove.confirm.action", comment: ""), role: .destructive) {
                    guard let pending = pendingLibraryRemoval else { return }
                    removeFromLibrary(itemID: pending.id, title: pending.title)
                    pendingLibraryRemoval = nil
                }
                Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {
                    pendingLibraryRemoval = nil
                }
            } message: {
                if let pending = pendingLibraryRemoval {
                    let baseMessage = String(
                        format: NSLocalizedString("library.remove.confirm.message", comment: ""),
                        pending.title
                    )
                    let notionNote = NSLocalizedString("library.remove.confirm.notion.note", comment: "")
                    Text(
                        "\(baseMessage)\n\n\(notionNote)"
                    )
                }
            }
            .alert(item: $activeAlert) { alert in
                switch alert {
                case .removalError(let message):
                    return Alert(
                        title: Text(NSLocalizedString("library.remove.failure.title", comment: "")),
                        message: Text(message),
                        dismissButton: .default(Text(NSLocalizedString("common.confirm", comment: ""))) {
                            DebugLogger.info("LibraryView: Alert OK tapped - type=removalError, activeAlert(atTap)=\(String(describing: activeAlert)), isGenerating=\(summaryService.isGenerating)")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                DebugLogger.info("LibraryView: Alert post-tap snapshot - type=removalError, activeAlert=\(String(describing: activeAlert)), isGenerating=\(summaryService.isGenerating)")
                            }
                        }
                    )
                case .summaryGenerationInProgress:
                    return Alert(
                        title: Text(NSLocalizedString("library.import.blocked.summary_in_progress.title", comment: "")),
                        message: Text(NSLocalizedString("library.import.blocked.summary_in_progress.message", comment: "")),
                        dismissButton: .default(Text(NSLocalizedString("common.confirm", comment: ""))) {
                            DebugLogger.info("LibraryView: Alert OK tapped - type=summaryGenerationInProgress, activeAlert(atTap)=\(String(describing: activeAlert)), isGenerating=\(summaryService.isGenerating), showingImportSheet=\(showingImportSheet)")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                DebugLogger.info("LibraryView: Alert post-tap snapshot - type=summaryGenerationInProgress, activeAlert=\(String(describing: activeAlert)), isGenerating=\(summaryService.isGenerating), showingImportSheet=\(showingImportSheet)")
                            }
                        }
                    )
                case .importError(let message):
                    return Alert(
                        title: Text(NSLocalizedString("library.import.result.title", comment: "")),
                        message: Text(message),
                        dismissButton: .default(Text(NSLocalizedString("common.confirm", comment: "")))
                    )
                }
            }
            .fullScreenCover(item: $readerLaunchTarget) { target in
                NavigationStack {
                    ReaderView(book: target.book, initialLocation: target.location)
                        .navigationBarHidden(true)
                }
                .environment(\.managedObjectContext, viewContext)
            }
            .onAppear {
                DebugLogger.info("LibraryView: 视图出现，刷新数据")
                BannerAdPreloadManager.shared.preloadSummaryBannerIfNeeded(trigger: "library_view_on_appear")
                refreshData()
            }
            .onReceive(NotificationCenter.default.publisher(for: ExternalBookImportDispatcher.didReceiveBookURL)) { notification in
                handleExternalImport(notification: notification)
            }
            .onChange(of: activeAlert) { newValue in
                DebugLogger.info("LibraryView: activeAlert changed -> \(String(describing: newValue)); isGenerating=\(summaryService.isGenerating), showingImportSheet=\(showingImportSheet)")
            }
        }
    }
    
    // 刷新数据的辅助方法
    private func refreshData() {
        DebugLogger.info("LibraryView: 执行数据刷新")
        
        // Update reading statuses (check for books that should be paused)
        ReadingStatusService.shared.updateAllReadingStatuses(in: viewContext)
        
        viewContext.refreshAllObjects()
        refreshID = UUID()
        DebugLogger.info("LibraryView: 数据刷新完成")
    }
    
    // 切换收藏状态
    private func toggleFavorite(for item: LibraryItem) {
        let newValue = !item.isFavorite
        item.isFavorite = newValue
        
        do {
            try viewContext.save()
            DebugLogger.info("LibraryView: 收藏状态切换成功 - \(item.book.displayTitle) -> \(newValue ? "已收藏" : "取消收藏")")
            refreshID = UUID()
        } catch {
            DebugLogger.error("LibraryView: 收藏状态保存失败", error: error)
        }
    }
    
    private func continueReading(_ book: Book) {
        DebugLogger.info("LibraryView: 继续阅读 - \(book.displayTitle)")
        readerLaunchTarget = ReaderLaunchTarget(book: book)
    }

    private func presentAISummary(for book: Book, source: String) {
        BannerAdPreloadManager.shared.preloadSummaryBannerIfNeeded(trigger: source)
        bookToShowAISummary = book
    }

    private func handleAddBookTapped() {
        if summaryService.isGenerating {
            DebugLogger.warning("LibraryView: AI 摘要生成中，阻止添加新书")
            activeAlert = .summaryGenerationInProgress
            return
        }

        showingImportSheet = true
    }

    private func handleExternalImport(notification: Notification) {
        guard let url = ExternalBookImportDispatcher.extractURL(from: notification) else {
            DebugLogger.warning("LibraryView: 收到外部导入通知，但无法解析文件 URL")
            return
        }

        guard ExternalBookImportDispatcher.isSupportedBookURL(url) else {
            DebugLogger.warning("LibraryView: 收到不支持的外部文件类型: \(url.absoluteString)")
            activeAlert = .importError(BookImportError.unsupportedFormat.localizedDescription)
            return
        }

        guard !importService.isImporting else {
            DebugLogger.warning("LibraryView: 当前已有导入任务，忽略新的外部导入请求")
            activeAlert = .importError(NSLocalizedString("library.import.in_progress", comment: ""))
            return
        }

        if summaryService.isGenerating {
            DebugLogger.warning("LibraryView: AI 摘要生成中，阻止外部导入")
            activeAlert = .summaryGenerationInProgress
            return
        }

        DebugLogger.info("LibraryView: 处理外部导入请求: \(url.absoluteString)")
        importBookFromExternalURL(url)
    }

    private func importBookFromExternalURL(_ url: URL) {
        let securityScopedAccessStarted = url.startAccessingSecurityScopedResource()
        if securityScopedAccessStarted {
            DebugLogger.info("LibraryView: 外部导入已开启安全作用域访问")
        } else {
            DebugLogger.info("LibraryView: 外部导入未开启安全作用域访问，继续尝试读取")
        }

        Task {
            defer {
                if securityScopedAccessStarted {
                    url.stopAccessingSecurityScopedResource()
                    DebugLogger.info("LibraryView: 外部导入已关闭安全作用域访问")
                }
            }

            do {
                let book = try await importService.importBook(from: url, context: viewContext)
                await MainActor.run {
                    DebugLogger.success("LibraryView: 外部导入成功 - \(book.displayTitle)")
                    refreshData()
                    presentAISummary(for: book, source: "external_book_import")
                }
            } catch {
                await MainActor.run {
                    DebugLogger.error("LibraryView: 外部导入失败", error: error)
                    activeAlert = .importError(error.localizedDescription)
                }
            }
        }
    }

    private func removeFromLibrary(itemID: NSManagedObjectID, title: String) {
        do {
            _ = try LibraryRemovalService.shared.remove(libraryItemID: itemID, in: viewContext)
            DebugLogger.success("LibraryView: 从书架移除成功 - \(title)")
            refreshData()
        } catch {
            DebugLogger.error("LibraryView: 从书架移除失败 - \(title)", error: error)
            activeAlert = .removalError(error.localizedDescription)
        }
    }

    private func resolveLibraryItem(by objectID: NSManagedObjectID) -> LibraryItem? {
        do {
            guard let item = try viewContext.existingObject(with: objectID) as? LibraryItem, !item.isDeleted else {
                return nil
            }
            return item
        } catch {
            DebugLogger.error("LibraryView: 解析 LibraryItem 失败", error: error)
            return nil
        }
    }

    private func resolveBook(from item: LibraryItem, actionName: String) -> Book? {
        guard let currentItem = resolveLibraryItem(by: item.objectID) else {
            DebugLogger.warning("LibraryView: \(actionName) 失败，LibraryItem 不存在")
            return nil
        }

        let book = currentItem.book
        if book.isDeleted {
            DebugLogger.warning("LibraryView: \(actionName) 失败，Book 已删除")
            return nil
        }

        return book
    }

    private func withResolvedBook(from item: LibraryItem, actionName: String, perform action: (Book) -> Void) {
        guard let book = resolveBook(from: item, actionName: actionName) else {
            DebugLogger.warning("LibraryView: \(actionName) 终止，触发数据刷新")
            refreshData()
            return
        }

        action(book)
    }
}

struct BookCardView: View {
    let libraryItem: LibraryItem
    var onTap: (() -> Void)? = nil
    var onSkim: (() -> Void)? = nil
    var onShowBookmarks: (() -> Void)? = nil
    var onShowHighlights: (() -> Void)? = nil
    var onShowInfo: (() -> Void)? = nil
    var onContinueReading: (() -> Void)? = nil
    var onToggleFavorite: (() -> Void)? = nil
    var onRemoveFromLibrary: (() -> Void)? = nil
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private var cardWidth: CGFloat {
        ResponsiveLayout.cardWidth(for: horizontalSizeClass)
    }
    
    private var cardHeight: CGFloat {
        cardWidth * 1.4
    }
    
    var body: some View {
        // Book Cover
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.8)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: cardWidth, height: cardHeight)
            
            if let coverImage = libraryItem.book.coverImage {
                coverImage
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: cardWidth, height: cardHeight)
                    .clipped()
                    .cornerRadius(12)
            } else {
                VStack {
                    Image(systemName: "book.closed")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                    
                    Text(libraryItem.book.displayTitle)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 8)
                }
            }
            
            // Progress Indicator, Favorite Badge and Status Badge
            VStack {
                HStack(spacing: 6) {
                    // Progress Indicator - show for all books with reading progress > 0
                    if let progress = libraryItem.book.readingProgress,
                       progress.progressPercentage > 0 {
                        ProgressIndicatorBadge(progress: progress.progressPercentage)
                    }
                    
                    Spacer()
                    
                    // Status Badge
                    StatusBadge(status: libraryItem.status)
                }
                Spacer()
                HStack {
                    // Favorite Badge - bottom left corner
                    if libraryItem.isFavorite {
                        FavoriteBadge()
                    }
                    Spacer()
                }
            }
            .padding(8)
        }
        .onTapGesture {
            onTap?()
        }
        .contextMenu {
            Button(action: { onSkim?() }) {
                Label(NSLocalizedString("skimming.mode.title", comment: ""), systemImage: "sparkles.rectangle.stack")
            }
            BookContextMenu(
                libraryItem: libraryItem,
                onContinueReading: onContinueReading,
                onShowBookmarks: onShowBookmarks,
                onShowHighlights: onShowHighlights,
                onShowInfo: onShowInfo,
                onToggleFavorite: onToggleFavorite,
                onRemoveFromLibrary: onRemoveFromLibrary
            )
        }
        .onAppear {
            // 调试：打印进度信息
            if let progress = libraryItem.book.readingProgress {
                DebugLogger.info("BookCard[\(libraryItem.book.displayTitle)]: 进度 = \(progress.progressPercentage * 100)%")
            } else {
                DebugLogger.info("BookCard[\(libraryItem.book.displayTitle)]: 没有进度数据")
            }
        }
    }
}

struct FavoriteBadge: View {
    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 12))
            .foregroundColor(.white)
            .padding(6)
            .background(Color.pink.opacity(0.9))
            .clipShape(Circle())
    }
}

struct StatusBadge: View {
    let status: ReadingStatus
    
    var body: some View {
        Text(status.displayNameKey)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.9))
            .foregroundColor(.white)
            .cornerRadius(8)
    }
    
    private var statusColor: Color {
        switch status {
        case .wantToRead:
            return .gray
        case .reading:
            return .blue
        case .finished:
            return .green
        case .paused:
            return .orange
        }
    }
}

struct ProgressIndicatorBadge: View {
    let progress: Double
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 10))
            Text(progressText)
                .font(.caption2)
                .fontWeight(.medium)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(progressColor.opacity(0.9))
        .foregroundColor(.white)
        .cornerRadius(8)
    }
    
    private var progressText: String {
        return String(format: "%.0f%%", progress * 100)
    }
    
    private var progressColor: Color {
        if progress < 0.3 {
            return .orange
        } else if progress < 0.7 {
            return .blue
        } else if progress < 1.0 {
            return .purple
        } else {
            return .green
        }
    }
}

struct ProgressBar: View {
    let progress: Double
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.black.opacity(0.3))
                    .frame(height: 4)
                
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .frame(width: geometry.size.width * progress, height: 4)
            }
        }
        .frame(height: 4)
    }
}

struct BookContextMenu: View {
    let libraryItem: LibraryItem
    var onContinueReading: (() -> Void)? = nil
    var onShowBookmarks: (() -> Void)? = nil
    var onShowHighlights: (() -> Void)? = nil
    var onShowInfo: (() -> Void)? = nil
    var onToggleFavorite: (() -> Void)? = nil
    var onRemoveFromLibrary: (() -> Void)? = nil
    
    var body: some View {
        if let onShowBookmarks = onShowBookmarks {
            Button(action: onShowBookmarks) {
                Label(NSLocalizedString("bookmark.list.title", comment: ""), systemImage: "bookmark")
            }
        }
        
        if let onShowHighlights = onShowHighlights {
            Button(action: onShowHighlights) {
                Label(NSLocalizedString("highlight.list.title", comment: ""), systemImage: "highlighter")
            }
        }
        
        Button(action: { onShowInfo?() }) {
            Label(NSLocalizedString("library.book_info.title", comment: ""), systemImage: "info.circle")
        }
        
        Button(action: { onToggleFavorite?() }) {
            if libraryItem.isFavorite {
                Label(NSLocalizedString("library.favorite.remove", comment: ""), systemImage: "heart.slash")
            } else {
                Label(NSLocalizedString("library.favorite.add", comment: ""), systemImage: "heart")
            }
        }
        
        Divider()
        
        Button(role: .destructive, action: {
            onRemoveFromLibrary?()
        }) {
            Label(NSLocalizedString("library.remove.action", comment: ""), systemImage: "trash")
        }
    }
}

private struct PendingLibraryRemoval: Identifiable {
    let id: NSManagedObjectID
    let title: String
}

private enum LibraryAlert: Identifiable, Equatable {
    case removalError(String)
    case summaryGenerationInProgress
    case importError(String)

    var id: String {
        switch self {
        case .removalError(let message):
            return "removalError_\(message)"
        case .summaryGenerationInProgress:
            return "summaryGenerationInProgress"
        case .importError(let message):
            return "importError_\(message)"
        }
    }
}

struct BookInfoSheet: View {
    let libraryItem: LibraryItem
    @Environment(\.dismiss) private var dismiss
    
    private var book: Book {
        libraryItem.book
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    
                    infoSection(title: NSLocalizedString("book.info.details", comment: "")) {
                        BookInfoRow(label: NSLocalizedString("book.info.author", comment: ""), value: book.displayAuthor)
                        BookInfoRow(label: NSLocalizedString("book.info.language", comment: ""), value: languageText)
                        BookInfoRow(label: NSLocalizedString("book.info.status", comment: ""), value: libraryItem.status.displayName)
                        BookInfoRow(label: NSLocalizedString("book.info.progress", comment: ""), value: progressText)
                        BookInfoRow(label: NSLocalizedString("book.info.added", comment: ""), value: formattedDate(libraryItem.addedAt))
                        BookInfoRow(label: NSLocalizedString("book.info.last_opened", comment: ""), value: formattedDate(libraryItem.lastAccessedAt))
                        BookInfoRow(label: NSLocalizedString("book.info.rating", comment: ""), value: ratingText)
                    }
                    
                    infoSection(title: NSLocalizedString("book.info.file", comment: "")) {
                        BookInfoRow(label: NSLocalizedString("book.info.file_format", comment: ""), value: book.fileFormat.uppercased())
                        BookInfoRow(label: NSLocalizedString("book.info.file_size", comment: ""), value: book.formattedFileSize)
                        BookInfoRow(label: NSLocalizedString("book.info.pages", comment: ""), value: "\(book.totalPages)")
                        BookInfoRow(label: NSLocalizedString("book.info.location", comment: ""), value: book.filePath)
                    }
                }
                .padding()
            }
            .navigationTitle(NSLocalizedString("library.book_info.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            DebugLogger.info("BookInfoSheet: 显示书籍信息 - \(book.displayTitle)")
        }
    }
    
    private var languageText: String {
        if let language = book.language, !language.isEmpty {
            let localizedName = Locale.current.localizedString(forLanguageCode: language)
            return localizedName ?? language
        }
        return NSLocalizedString("book.info.unknown", comment: "")
    }
    
    private var progressText: String {
        if let progress = book.readingProgress {
            return String(format: "%.0f%%", progress.progressPercentage * 100)
        }
        return NSLocalizedString("book.info.unknown", comment: "")
    }
    
    private var ratingText: String {
        if libraryItem.hasRating {
            return libraryItem.ratingStars
        }
        return NSLocalizedString("book.info.rating.not_set", comment: "")
    }
    
    private var headerSection: some View {
        HStack(alignment: .top, spacing: 16) {
            coverView
            
            VStack(alignment: .leading, spacing: 8) {
                Text(book.displayTitle)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                Text(book.displayAuthor)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                StatusBadge(status: libraryItem.status)
            }
            
            Spacer()
        }
    }
    
    private var coverView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.08))
                .frame(width: 90, height: 130)
            
            if let coverImage = book.coverImage {
                coverImage
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 90, height: 130)
                    .clipped()
                    .cornerRadius(12)
            } else {
                Image(systemName: "book.closed")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private func infoSection(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            VStack(spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.primary.opacity(0.03))
            .cornerRadius(12)
        }
    }
    
    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return NSLocalizedString("book.info.unknown", comment: "") }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct BookInfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.footnote)
                .foregroundColor(.secondary)
            
            Spacer(minLength: 12)
            
            Text(value)
                .font(.footnote)
                .foregroundColor(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct ReaderLaunchTarget: Identifiable {
    let id = UUID()
    let book: Book
    let location: BookmarkLocation?
    
    init(book: Book, location: BookmarkLocation? = nil) {
        self.book = book
        self.location = location
    }
}

private struct ReaderColorOption: Identifiable {
    let id: String
    let titleKey: String
    let hex: String
    let swipeTintHex: String

    var title: String {
        NSLocalizedString(titleKey, comment: "")
    }

    var swipeTintColor: Color {
        Color(hex: swipeTintHex) ?? (Color(hex: hex) ?? .gray)
    }
}

private enum ReaderColorPalette {
    static let bookmarkOptions: [ReaderColorOption] = [
        ReaderColorOption(id: "bookmark-white", titleKey: "color.option.white", hex: Bookmark.defaultColorHex, swipeTintHex: "D9D9D9"),
        ReaderColorOption(id: "bookmark-mint", titleKey: "color.option.mint", hex: "D6EFDE", swipeTintHex: "B7DEC3"),
        ReaderColorOption(id: "bookmark-blue", titleKey: "color.option.blue", hex: "D4E7FF", swipeTintHex: "B2D0F4"),
        ReaderColorOption(id: "bookmark-peach", titleKey: "color.option.peach", hex: "FFDCC8", swipeTintHex: "F2BEA4")
    ]

    static let highlightOptions: [ReaderColorOption] = [
        ReaderColorOption(id: "highlight-yellow", titleKey: "color.option.yellow", hex: Color.yellow.hexString, swipeTintHex: "E5C949"),
        ReaderColorOption(id: "highlight-green", titleKey: "color.option.green", hex: "D6EFD6", swipeTintHex: "B6DBB6"),
        ReaderColorOption(id: "highlight-blue", titleKey: "color.option.blue", hex: "D4E7FF", swipeTintHex: "B2D0F4"),
        ReaderColorOption(id: "highlight-pink", titleKey: "color.option.pink", hex: "FFD3E5", swipeTintHex: "F0B1CB")
    ]
}

struct BookmarkListSheet: View {
    let book: Book
    var onSelect: (BookmarkLocation) -> Void
    
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @FetchRequest private var bookmarks: FetchedResults<Bookmark>
    
    init(book: Book, onSelect: @escaping (BookmarkLocation) -> Void) {
        self.book = book
        self.onSelect = onSelect
        _bookmarks = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Bookmark.createdAt, ascending: false)],
            predicate: NSPredicate(format: "book == %@", book)
        )
    }
    
    var body: some View {
        NavigationStack {
            List {
                if bookmarks.isEmpty {
                    bookmarkEmptyState
                } else {
                    ForEach(bookmarks) { bookmark in
                        Button(action: {
                            onSelect(bookmark.location)
                            dismiss()
                        }) {
                            bookmarkRow(for: bookmark)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            ForEach(ReaderColorPalette.bookmarkOptions) { option in
                                bookmarkColorSwipeButton(option, for: bookmark)
                            }
                        }
                    }
                    .onDelete(perform: deleteBookmarks)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(NSLocalizedString("bookmark.list.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !bookmarks.isEmpty {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var bookmarkEmptyState: some View {
        VStack(alignment: .center, spacing: 12) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(.secondary)
            Text(NSLocalizedString("bookmark.list.empty", comment: ""))
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(book.displayTitle)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }
    
    private func bookmarkRow(for bookmark: Bookmark) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(bookmark.bookmarkColor)
                    .frame(width: 10, height: 10)
                Text(bookmark.displayTitle)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                Spacer(minLength: 12)
                Text(bookmark.displayPage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(bookmark.bookmarkColor.opacity(0.56))
                    .cornerRadius(10)
            }
            
            HStack(spacing: 12) {
                Label(
                    String(format: NSLocalizedString("bookmark.chapter_format", comment: ""), Int(bookmark.chapterIndex) + 1),
                    systemImage: "text.book.closed"
                )
                .font(.caption)
                .foregroundColor(.secondary)
                
                Label(
                    String(format: NSLocalizedString("bookmark.page_format", comment: ""), Int(bookmark.pageIndex) + 1),
                    systemImage: "rectangle.and.pencil.and.ellipsis"
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Text(bookmark.formattedDate)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(bookmark.bookmarkColor.opacity(0.34))
        )
    }
    
    private func deleteBookmarks(at offsets: IndexSet) {
        offsets.map { bookmarks[$0] }.forEach { bookmark in
            viewContext.delete(bookmark)
        }
        
        do {
            try viewContext.save()
            DebugLogger.info("BookmarkListSheet: 删除书签完成")
        } catch {
            DebugLogger.error("BookmarkListSheet: 删除书签失败", error: error)
        }
    }

    private func bookmarkColorSwipeButton(_ option: ReaderColorOption, for bookmark: Bookmark) -> some View {
        return Button {
            applyBookmarkColor(option.hex, to: bookmark)
        } label: {
            Color.clear
                .frame(width: 10, height: 22)
        }
        .tint(option.swipeTintColor)
        .accessibilityLabel(Text(option.title))
    }

    private func applyBookmarkColor(_ hex: String, to bookmark: Bookmark) {
        bookmark.colorHex = hex

        do {
            try viewContext.save()
            DebugLogger.info("BookmarkListSheet: 书签颜色已更新 - \(bookmark.id.uuidString)")
        } catch {
            DebugLogger.error("BookmarkListSheet: 更新书签颜色失败", error: error)
        }
    }
}

struct HighlightListSheet: View {
    let book: Book
    var onSelect: ((BookmarkLocation) -> Void)? = nil
    
    @StateObject private var appSettings = AppSettings.shared
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @FetchRequest private var highlights: FetchedResults<Highlight>
    @State private var editingHighlight: Highlight?
    @State private var noteDraft = ""
    @State private var activeAlert: HighlightListAlert?
    @State private var sharePreviewPayload: HighlightSharePreviewPayload?
    @State private var showingExportFormatPicker = false
    @State private var exportSharePayload: HighlightExportSharePayload?
    @State private var exportFileURLToCleanup: URL?
    @State private var isPreparingMarkdownExport = false
    @State private var generatingShareHighlightObjectID: NSManagedObjectID?
    @State private var isSelecting = false
    @State private var selectedHighlightObjectIDs: Set<NSManagedObjectID> = []
    @FocusState private var isNoteEditorFocused: Bool

    private struct HighlightListAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String?
    }

    private struct HighlightSharePreviewPayload: Identifiable {
        let id = UUID()
        let image: UIImage
        let cardPayload: HighlightShareCardPayload
    }

    private struct HighlightExportSharePayload: Identifiable {
        let id = UUID()
        let activityItems: [Any]
    }

    private struct HighlightMarkdownExportEntry {
        let chapterTitle: String
        let highlightText: String
        let noteText: String?
        let createdAt: Date
        let updatedAt: Date
    }
    
    init(book: Book, onSelect: ((BookmarkLocation) -> Void)? = nil) {
        self.book = book
        self.onSelect = onSelect
        _highlights = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Highlight.updatedAt, ascending: false)],
            predicate: NSPredicate(format: "book == %@", book)
        )
    }
    
    var body: some View {
        NavigationStack {
            List {
                if highlights.isEmpty {
                    highlightEmptyState
                } else {
                    ForEach(displayedHighlights, id: \.objectID) { highlight in
                        highlightRow(for: highlight)
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                if !isSelecting {
                                    ForEach(ReaderColorPalette.highlightOptions) { option in
                                        highlightColorSwipeButton(option, for: highlight)
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if !isSelecting {
                                    Button(role: .destructive) {
                                        deleteHighlight(highlight)
                                    } label: {
                                        Label(NSLocalizedString("highlight.list.delete", comment: ""), systemImage: "trash")
                                    }
                                    .tint(.red)
                                }
                            }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text(NSLocalizedString("common.back", comment: ""))
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isSelecting {
                        HStack(spacing: 8) {
                            Button(NSLocalizedString("common.cancel", comment: "")) {
                                exitSelectionMode()
                            }
                            Button(NSLocalizedString("highlight.list.merge", comment: "")) {
                                mergeSelectedHighlights()
                            }
                            .disabled(selectedHighlightObjectIDs.count < 2)
                        }
                    } else {
                        HStack(spacing: 8) {
                            exportToolbarButton
                            Button(NSLocalizedString("common.select", comment: "")) {
                                enterSelectionMode()
                            }
                            Menu {
                                Picker(
                                    NSLocalizedString("settings.highlight_sort.title", comment: ""),
                                    selection: $appSettings.highlightSortMode
                                ) {
                                    ForEach(HighlightSortMode.allCases, id: \.rawValue) { mode in
                                        Text(mode.displayName).tag(mode)
                                    }
                                }
                            } label: {
                                Image(systemName: "arrow.up.arrow.down")
                                    .accessibilityLabel(Text(NSLocalizedString("settings.highlight_sort.title", comment: "")))
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $editingHighlight) { highlight in
            noteEditorSheet(for: highlight)
        }
        .sheet(item: $sharePreviewPayload) { payload in
            HighlightSharePreviewSheet(initialImage: payload.image, cardPayload: payload.cardPayload)
        }
        .sheet(item: $exportSharePayload, onDismiss: handleExportShareDismiss) { payload in
            HighlightListActivityShareSheet(activityItems: payload.activityItems) { _, completed, _, error in
                if let error {
                    DebugLogger.error("HighlightListSheet: Markdown 导出分享失败", error: error)
                    return
                }
                DebugLogger.info("HighlightListSheet: Markdown 导出分享面板结束，completed=\(completed)")
            }
        }
        .confirmationDialog(
            NSLocalizedString("highlight.export.choose_format.title", comment: ""),
            isPresented: $showingExportFormatPicker,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("highlight.export.format.markdown", comment: "")) {
                exportHighlightsAsMarkdown()
            }
        }
        .alert(item: $activeAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: alert.message.map(Text.init),
                dismissButton: .default(Text(NSLocalizedString("common.confirm", comment: "")))
            )
        }
        .onAppear {
            DebugLogger.info("HighlightListSheet: 显示书籍高亮/笔记列表 - \(book.displayTitle)")
            viewContext.refreshAllObjects()
        }
        .onDisappear {
            exitSelectionMode()
        }
    }

    private var displayedHighlights: [Highlight] {
        switch appSettings.highlightSortMode {
        case .modifiedTime:
            return highlights.sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.createdAt > rhs.createdAt
            }
        case .chapter:
            return highlights.sorted(by: compareByChapter)
        }
    }

    private func compareByChapter(_ lhs: Highlight, _ rhs: Highlight) -> Bool {
        let leftLocation = lhs.readingLocation
        let rightLocation = rhs.readingLocation

        switch (leftLocation, rightLocation) {
        case let (.some(left), .some(right)):
            if left.chapterIndex != right.chapterIndex {
                return left.chapterIndex < right.chapterIndex
            }
            if left.pageIndex != right.pageIndex {
                return left.pageIndex < right.pageIndex
            }
            let leftOffset = left.textOffset ?? Int.max
            let rightOffset = right.textOffset ?? Int.max
            if leftOffset != rightOffset {
                return leftOffset < rightOffset
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.updatedAt > rhs.updatedAt
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.createdAt > rhs.createdAt
        }
    }
    
    private var highlightEmptyState: some View {
        VStack(alignment: .center, spacing: 12) {
            Image(systemName: "highlighter")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(.secondary)
            Text(NSLocalizedString("highlight.list.empty", comment: ""))
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(book.displayTitle)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }

    private var exportToolbarButton: some View {
        Button(action: { showingExportFormatPicker = true }) {
            if isPreparingMarkdownExport {
                ProgressView()
            } else {
                Text(NSLocalizedString("highlight.export.button", comment: ""))
            }
        }
        .disabled(displayedHighlights.isEmpty || isPreparingMarkdownExport || generatingShareHighlightObjectID != nil)
    }
    
    private func highlightRow(for highlight: Highlight) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if isSelecting {
                Image(systemName: selectedHighlightObjectIDs.contains(highlight.objectID) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selectedHighlightObjectIDs.contains(highlight.objectID) ? .accentColor : .secondary)
                    .font(.title3)
                    .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(highlight.highlightColor)
                        .frame(width: 10, height: 10)
                    Text(chapterLabel(for: highlight))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Spacer(minLength: 12)
                    Text(highlight.formattedDate)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if canOpenHighlightLocation(highlight) {
                    Button(action: { openHighlightLocation(for: highlight) }) {
                        Text(highlight.displayText)
                            .font(.body)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(highlight.highlightColor.opacity(0.48))
                            .cornerRadius(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(highlight.displayText)
                        .font(.body)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(highlight.highlightColor.opacity(0.48))
                        .cornerRadius(10)
                }

                if let noteText = noteText(for: highlight) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "note.text")
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                        MarkdownText(noteText, lineSpacing: 4)
                            .foregroundColor(.primary)
                    }
                } else {
                    Label(NSLocalizedString("highlight.action.no_note", comment: ""), systemImage: "note.text")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                if !isSelecting {
                    HStack(spacing: 12) {
                        Spacer(minLength: 8)
                        inlineActionButtons(for: highlight)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isSelecting else { return }
            toggleSelection(for: highlight)
        }
    }

    private func canOpenHighlightLocation(_ highlight: Highlight) -> Bool {
        guard !isSelecting else { return false }
        guard onSelect != nil else { return false }
        guard highlight.readingLocation != nil else { return false }
        return !highlight.isMergedFromHighlights
    }
    
    private func chapterLabel(for highlight: Highlight) -> String {
        if let chapter = highlight.chapter?.trimmingCharacters(in: .whitespacesAndNewlines), !chapter.isEmpty {
            return chapter
        }
        return NSLocalizedString("highlight.list.unknown_chapter", comment: "")
    }
    
    private func pageLabel(for highlight: Highlight) -> String {
        let pageIndex = Int(highlight.pageNumber)
        return String(format: NSLocalizedString("bookmark.page_format", comment: ""), max(pageIndex, 0) + 1)
    }
    
    private func noteText(for highlight: Highlight) -> String? {
        guard let note = highlight.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else {
            return nil
        }
        return note
    }

    private func noteActionTitle(for highlight: Highlight) -> String {
        noteText(for: highlight) == nil
            ? NSLocalizedString("reader.note.add", comment: "")
            : NSLocalizedString("highlight.list.edit_note", comment: "")
    }

    @ViewBuilder
    private func inlineActionButtons(for highlight: Highlight) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                noteActionButton(for: highlight, compact: false)
                shareActionButton(for: highlight, compact: false)
                deleteActionButton(for: highlight, compact: false)
            }

            HStack(spacing: 8) {
                noteActionButton(for: highlight, compact: true)
                shareActionButton(for: highlight, compact: true)
                deleteActionButton(for: highlight, compact: true)
            }
        }
    }

    private func noteActionButton(for highlight: Highlight, compact: Bool) -> some View {
        Button(action: { openNoteEditor(for: highlight) }) {
            if compact {
                Image(systemName: "square.and.pencil")
            } else {
                Label(noteActionTitle(for: highlight), systemImage: "square.and.pencil")
                    .labelStyle(.titleAndIcon)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func shareActionButton(for highlight: Highlight, compact: Bool) -> some View {
        Button(action: { generateSharePreview(for: highlight) }) {
            if isGeneratingShare(for: highlight) {
                ProgressView()
            } else if compact {
                Image(systemName: "square.and.arrow.up")
            } else {
                Label(NSLocalizedString("highlight.list.share_note", comment: ""), systemImage: "square.and.arrow.up")
                    .labelStyle(.titleAndIcon)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize(horizontal: true, vertical: false)
        .disabled(generatingShareHighlightObjectID != nil)
    }

    private func deleteActionButton(for highlight: Highlight, compact: Bool) -> some View {
        Button(role: .destructive, action: { deleteHighlight(highlight) }) {
            if compact {
                Image(systemName: "trash")
            } else {
                Label(NSLocalizedString("highlight.list.delete", comment: ""), systemImage: "trash")
                    .labelStyle(.titleAndIcon)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize(horizontal: true, vertical: false)
        .tint(.red)
    }

    private func openNoteEditor(for highlight: Highlight) {
        noteDraft = highlight.note ?? ""
        editingHighlight = highlight
    }

    private func generateSharePreview(for highlight: Highlight) {
        let payload = HighlightShareCardPayload.make(
            highlightText: highlight.displayText,
            noteText: noteText(for: highlight),
            bookTitle: book.displayTitle,
            chapterTitle: highlight.chapter,
            chapterFallback: NSLocalizedString("highlight.list.unknown_chapter", comment: ""),
            footerText: NSLocalizedString("highlight.share.footer", comment: ""),
            footerSubtitleText: NSLocalizedString("highlight.share.footer_subtitle", comment: ""),
            coverImageData: book.coverImageData
        )
        let highlightObjectID = highlight.objectID
        generatingShareHighlightObjectID = highlightObjectID
        DebugLogger.info("HighlightListSheet: 开始生成分享图 - \(book.displayTitle)")

        Task {
            do {
                let image = try await HighlightShareCardRenderer.renderImage(payload: payload, frameStyle: .none)
                await MainActor.run {
                    generatingShareHighlightObjectID = nil
                    sharePreviewPayload = HighlightSharePreviewPayload(image: image, cardPayload: payload)
                    DebugLogger.info("HighlightListSheet: 分享图生成成功 - \(book.displayTitle)")
                }
            } catch {
                await MainActor.run {
                    generatingShareHighlightObjectID = nil
                    activeAlert = HighlightListAlert(
                        title: NSLocalizedString("highlight.share.generate_failed.title", comment: ""),
                        message: NSLocalizedString("highlight.share.generate_failed.message", comment: "")
                    )
                }
                DebugLogger.error("HighlightListSheet: 分享图生成失败", error: error)
            }
        }
    }

    private func isGeneratingShare(for highlight: Highlight) -> Bool {
        generatingShareHighlightObjectID == highlight.objectID
    }

    private func enterSelectionMode() {
        isSelecting = true
        selectedHighlightObjectIDs.removeAll()
    }

    private func exitSelectionMode() {
        isSelecting = false
        selectedHighlightObjectIDs.removeAll()
    }

    private func toggleSelection(for highlight: Highlight) {
        if selectedHighlightObjectIDs.contains(highlight.objectID) {
            selectedHighlightObjectIDs.remove(highlight.objectID)
        } else {
            selectedHighlightObjectIDs.insert(highlight.objectID)
        }
    }

    private func mergeSelectedHighlights() {
        let selectedItems = displayedHighlights.filter { selectedHighlightObjectIDs.contains($0.objectID) }
        guard selectedItems.count >= 2,
              let first = selectedItems.first,
              let last = selectedItems.last else {
            return
        }

        let mergedText = selectedItems
            .map { $0.selectedText.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        guard !mergedText.isEmpty else {
            return
        }

        let mergedNote = selectedItems
            .compactMap { noteText(for: $0) }
            .joined(separator: "\n\n")

        let mergedHighlight = Highlight(context: viewContext)
        mergedHighlight.id = UUID()
        mergedHighlight.selectedText = mergedText
        let firstLocation = first.readingLocation
        mergedHighlight.startPosition = Highlight.markStartPositionAsMerged(
            first.startPosition,
            fallbackChapterIndex: firstLocation?.chapterIndex ?? 0,
            fallbackPageIndex: firstLocation?.pageIndex ?? max(Int(first.pageNumber), 0),
            fallbackOffset: firstLocation?.textOffset
        )
        mergedHighlight.endPosition = last.endPosition
        mergedHighlight.chapter = first.chapter
        mergedHighlight.pageNumber = first.pageNumber
        // Color strategy: keep the first selected highlight color when inconsistent.
        mergedHighlight.colorHex = first.colorHex
        mergedHighlight.note = mergedNote.isEmpty ? nil : mergedNote
        mergedHighlight.createdAt = first.createdAt
        mergedHighlight.updatedAt = Date()
        mergedHighlight.book = book

        selectedItems.forEach { viewContext.delete($0) }

        do {
            try viewContext.save()
            if let editingHighlight, selectedHighlightObjectIDs.contains(editingHighlight.objectID) {
                self.editingHighlight = nil
            }
            if let generatingShareHighlightObjectID, selectedHighlightObjectIDs.contains(generatingShareHighlightObjectID) {
                self.generatingShareHighlightObjectID = nil
            }
            DebugLogger.info("HighlightListSheet: 合并高亮成功，数量=\(selectedItems.count)")
            exitSelectionMode()
        } catch {
            DebugLogger.error("HighlightListSheet: 合并高亮失败", error: error)
            activeAlert = HighlightListAlert(
                title: NSLocalizedString("reader.highlight.save_failed", comment: ""),
                message: nil
            )
        }
    }

    private func deleteHighlight(_ highlight: Highlight) {
        let highlightObjectID = highlight.objectID
        viewContext.delete(highlight)

        do {
            try viewContext.save()
            if generatingShareHighlightObjectID == highlightObjectID {
                generatingShareHighlightObjectID = nil
            }
            if editingHighlight?.objectID == highlightObjectID {
                editingHighlight = nil
            }
            DebugLogger.info("HighlightListSheet: 删除高亮成功 - \(highlightObjectID.uriRepresentation().absoluteString)")
        } catch {
            DebugLogger.error("HighlightListSheet: 删除高亮失败", error: error)
            activeAlert = HighlightListAlert(
                title: NSLocalizedString("reader.highlight.save_failed", comment: ""),
                message: nil
            )
        }
    }

    private func highlightColorSwipeButton(_ option: ReaderColorOption, for highlight: Highlight) -> some View {
        return Button {
            applyHighlightColor(option.hex, to: highlight)
        } label: {
            Color.clear
                .frame(width: 10, height: 22)
        }
        .tint(option.swipeTintColor)
        .accessibilityLabel(Text(option.title))
    }

    private func applyHighlightColor(_ hex: String, to highlight: Highlight) {
        highlight.colorHex = hex
        highlight.updatedAt = Date()

        do {
            try viewContext.save()
            DebugLogger.info("HighlightListSheet: 高亮颜色已更新 - \(highlight.id.uuidString)")
        } catch {
            DebugLogger.error("HighlightListSheet: 更新高亮颜色失败", error: error)
            activeAlert = HighlightListAlert(
                title: NSLocalizedString("reader.highlight.save_failed", comment: ""),
                message: nil
            )
        }
    }

    private func openHighlightLocation(for highlight: Highlight) {
        guard !highlight.isMergedFromHighlights else {
            DebugLogger.info("[HighlightNav] 跳过合并高亮跳转: highlight=\(highlight.id.uuidString)")
            return
        }
        DebugLogger.info("[HighlightNav] openHighlightLocation: startPosition=\(highlight.startPosition), selectedText前20字=\(String(highlight.selectedText.prefix(20)))")
        guard let location = highlight.readingLocation else {
            DebugLogger.info("[HighlightNav] 跳转失败，readingLocation 为 nil")
            return
        }
        DebugLogger.info("[HighlightNav] 准备跳转: chapter=\(location.chapterIndex), page=\(location.pageIndex), textOffset=\(location.textOffset.map(String.init) ?? "nil"), onSelect=\(onSelect != nil ? "有" : "无")")

        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            DebugLogger.info("[HighlightNav] 延迟回调触发，调用 onSelect")
            onSelect?(location)
        }
    }

    private func saveEditedNote() {
        guard let highlight = editingHighlight else { return }

        let trimmedNote = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        highlight.note = trimmedNote.isEmpty ? nil : trimmedNote
        highlight.updatedAt = Date()

        do {
            try viewContext.save()
            DebugLogger.info("HighlightListSheet: 笔记保存成功 - \(book.displayTitle)")
            editingHighlight = nil
        } catch {
            DebugLogger.error("HighlightListSheet: 笔记保存失败", error: error)
            activeAlert = HighlightListAlert(
                title: NSLocalizedString("reader.highlight.save_failed", comment: ""),
                message: nil
            )
        }
    }

    private func handleExportShareDismiss() {
        guard let fileURL = exportFileURLToCleanup else { return }
        cleanupShareFile(at: fileURL)
        exportFileURLToCleanup = nil
    }

    private func exportHighlightsAsMarkdown() {
        guard !displayedHighlights.isEmpty else { return }

        let snapshot = displayedHighlights.map { highlight in
            HighlightMarkdownExportEntry(
                chapterTitle: chapterLabel(for: highlight),
                highlightText: highlight.displayText,
                noteText: noteText(for: highlight),
                createdAt: highlight.createdAt,
                updatedAt: highlight.updatedAt
            )
        }
        let sortModeDisplayName = appSettings.highlightSortMode.displayName
        let bookTitle = book.displayTitle
        let exportedAt = Date()
        isPreparingMarkdownExport = true
        DebugLogger.info("HighlightListSheet: 开始导出 Markdown - \(bookTitle), count=\(snapshot.count)")

        do {
            let markdown = buildMarkdownDocument(
                entries: snapshot,
                bookTitle: bookTitle,
                sortModeDisplayName: sortModeDisplayName,
                exportedAt: exportedAt
            )
            let fileURL = try writeMarkdownExport(markdown, bookTitle: bookTitle, exportedAt: exportedAt)
            if let staleURL = exportFileURLToCleanup {
                cleanupShareFile(at: staleURL)
            }
            exportFileURLToCleanup = fileURL
            exportSharePayload = HighlightExportSharePayload(activityItems: [fileURL])
            isPreparingMarkdownExport = false
            DebugLogger.info("HighlightListSheet: Markdown 导出成功 - \(fileURL.lastPathComponent)")
        } catch {
            isPreparingMarkdownExport = false
            activeAlert = HighlightListAlert(
                title: NSLocalizedString("settings.export.failed", comment: ""),
                message: NSLocalizedString("highlight.export.failed.message", comment: "")
            )
            DebugLogger.error("HighlightListSheet: Markdown 导出失败", error: error)
        }
    }

    private func buildMarkdownDocument(
        entries: [HighlightMarkdownExportEntry],
        bookTitle: String,
        sortModeDisplayName: String,
        exportedAt: Date
    ) -> String {
        let metadataDateFormatter = ISO8601DateFormatter()
        metadataDateFormatter.formatOptions = [.withInternetDateTime]

        let displayDateFormatter = DateFormatter()
        displayDateFormatter.locale = Locale.autoupdatingCurrent
        displayDateFormatter.dateStyle = .medium
        displayDateFormatter.timeStyle = .short

        var sections: [String] = []
        sections.append("---")
        sections.append("title: \"\(yamlEscaped(bookTitle)) - Highlights Export\"")
        sections.append("book: \"\(yamlEscaped(bookTitle))\"")
        sections.append("exported_at: \"\(metadataDateFormatter.string(from: exportedAt))\"")
        sections.append("sort_order: \"\(yamlEscaped(sortModeDisplayName))\"")
        sections.append("total_entries: \(entries.count)")
        sections.append("---")
        sections.append("")
        sections.append("# Highlights & Notes")
        sections.append("")
        sections.append("- **Book**: \(bookTitle)")
        sections.append("- **Exported At**: \(displayDateFormatter.string(from: exportedAt))")
        sections.append("- **Sort Order**: \(sortModeDisplayName)")
        sections.append("- **Total Entries**: \(entries.count)")
        sections.append("")
        sections.append("---")

        for (index, entry) in entries.enumerated() {
            sections.append("")
            sections.append("## \(index + 1). \(entry.chapterTitle)")
            sections.append("")
            sections.append("- **Created**: \(displayDateFormatter.string(from: entry.createdAt))")
            if entry.updatedAt != entry.createdAt {
                sections.append("- **Updated**: \(displayDateFormatter.string(from: entry.updatedAt))")
            }
            sections.append("")
            sections.append("### Highlight")
            sections.append(markdownBlockquote(from: entry.highlightText))
            sections.append("")
            sections.append("### Note")
            if let noteText = entry.noteText {
                sections.append(normalizeLineEndings(noteText))
            } else {
                sections.append("_No note_")
            }
            sections.append("")
            sections.append("---")
        }

        return sections.joined(separator: "\n")
    }

    private func writeMarkdownExport(_ markdown: String, bookTitle: String, exportedAt: Date) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        let sanitizedTitle = sanitizedFilenameComponent(from: bookTitle)
        let fileName = "\(sanitizedTitle)-highlights-\(formatter.string(from: exportedAt)).md"
        let exportURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        try markdown.write(to: exportURL, atomically: true, encoding: .utf8)
        return exportURL
    }

    private func markdownBlockquote(from text: String) -> String {
        let normalized = normalizeLineEndings(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "> " }
        return normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                line.isEmpty ? ">" : "> \(line)"
            }
            .joined(separator: "\n")
    }

    private func normalizeLineEndings(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func yamlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func sanitizedFilenameComponent(from rawValue: String) -> String {
        let forbiddenCharacterSet = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let collapsed = rawValue
            .components(separatedBy: forbiddenCharacterSet)
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let fallback = collapsed.isEmpty ? "LanRead" : collapsed
        return String(fallback.prefix(60))
    }

    private func cleanupShareFile(at fileURL: URL) {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            DebugLogger.error("HighlightListSheet: 清理分享临时文件失败", error: error)
        }
    }

    private func noteEditorSheet(for highlight: Highlight) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(highlight.displayText)
                    .font(.system(size: 15, design: .serif))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(10)

                TextEditor(text: $noteDraft)
                    .font(.body)
                    .focused($isNoteEditorFocused)
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
            .navigationTitle(noteText(for: highlight) == nil
                ? NSLocalizedString("reader.note.add", comment: "")
                : NSLocalizedString("highlight.list.edit_note", comment: ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("common.cancel", comment: "")) {
                        isNoteEditorFocused = false
                        editingHighlight = nil
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("common.save", comment: "")) {
                        isNoteEditorFocused = false
                        saveEditedNote()
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    isNoteEditorFocused = true
                }
            }
            .onDisappear {
                isNoteEditorFocused = false
            }
        }
    }
}

private struct HighlightListActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let completion: UIActivityViewController.CompletionWithItemsHandler?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.completionWithItemsHandler = completion
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct EmptyLibraryView: View {
    var onImportTap: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "books.vertical")
                .font(.system(size: 80))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text(NSLocalizedString("library.empty.title", comment: ""))
                    .font(.title2)
                    .fontWeight(.medium)
                
                Text(NSLocalizedString("library.empty.subtitle", comment: ""))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: { onImportTap?() }) {
                HStack {
                    Image(systemName: "plus")
                    Text(NSLocalizedString("library.import.title", comment: ""))
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.accentColor)
                .cornerRadius(25)
            }
            
            Spacer()
        }
        .padding()
    }
}

struct FilterSheetView: View {
    @Binding var selectedFilter: LibraryFilterType
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                // General section
                Section {
                    filterButton(for: .all)
                    filterButton(for: .favorites)
                }
                
                // Reading Status section
                Section(NSLocalizedString("library.filter.reading_status", comment: "")) {
                    ForEach(ReadingStatus.allCases, id: \.rawValue) { status in
                        filterButton(for: .status(status))
                    }
                }
            }
            .navigationTitle(NSLocalizedString("library.filter.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "")) {
                        dismiss()
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    Button(NSLocalizedString("common.done", comment: "")) {
                        dismiss()
                    }
                }
                #endif
            }
        }
    }
    
    @ViewBuilder
    private func filterButton(for filter: LibraryFilterType) -> some View {
        Button(action: {
            selectedFilter = filter
            dismiss()
        }) {
            HStack {
                // Icon for special filters
                if case .favorites = filter {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.pink)
                }
                
                Text(filter.displayNameKey)
                Spacer()
                if selectedFilter == filter {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
        }
        .foregroundColor(.primary)
    }
}

struct ImportBookView: View {
    var onBookImported: ((Book) -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var importService = BookImportService.shared
    
    @State private var showingFilePicker = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var importedBook: Book?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()
                
                if importService.isImporting {
                    VStack(spacing: 16) {
                        ProgressView(value: importService.importProgress)
                            .progressViewStyle(LinearProgressViewStyle())
                            .frame(maxWidth: 200)
                        
                        Text(NSLocalizedString("library.import.in_progress", comment: ""))
                            .font(.headline)
                        
                        Text("\(Int(importService.importProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 60))
                        .foregroundColor(.accentColor)
                    
                    VStack(spacing: 16) {
                        Text(NSLocalizedString("library.import.sheet.title", comment: ""))
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text(NSLocalizedString("library.import.sheet.description", comment: ""))
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    VStack(spacing: 16) {
                        Button(action: { showingFilePicker = true }) {
                            HStack {
                                Image(systemName: "folder")
                                Text(NSLocalizedString("library.import.source.files_app", comment: ""))
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .cornerRadius(12)
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle(NSLocalizedString("library.import.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.cancel", comment: "")) {
                        dismiss()
                    }
                    .disabled(importService.isImporting)
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.epub],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result: result)
            }
            .alert(NSLocalizedString("library.import.result.title", comment: ""), isPresented: $showingAlert) {
                Button(NSLocalizedString("common.confirm", comment: "")) {
                    if importedBook != nil {
                        dismiss()
                    }
                }
            } message: {
                Text(alertMessage)
            }
            .onChange(of: importService.importError) { error in
                if let error = error {
                    alertMessage = error
                    showingAlert = true
                }
            }
        }
    }
    
    private func handleFileImport(result: Result<[URL], Error>) {
        DebugLogger.info("开始处理文件导入")
        
        switch result {
        case .success(let urls):
            DebugLogger.info("文件选择成功，URL数量: \(urls.count)")
            
            guard let url = urls.first else { 
                DebugLogger.error("没有选择任何文件")
                return 
            }
            importBook(from: url, usesSecurityScopedResource: true)
            
        case .failure(let error):
            DebugLogger.error("文件选择失败: \(error.localizedDescription)")
            DebugLogger.error("错误详情: \(error)")
            alertMessage = "选择文件时出错：\(error.localizedDescription)"
            showingAlert = true
        }
    }

    private func importBook(from url: URL, usesSecurityScopedResource: Bool) {
        DebugLogger.info("选择的文件URL: \(url.absoluteString)")
        DebugLogger.info("文件路径: \(url.path)")
        DebugLogger.info("文件扩展名: \(url.pathExtension)")

        var securityScopedAccessStarted = false
        if usesSecurityScopedResource {
            DebugLogger.info("尝试开始安全访问文件")
            securityScopedAccessStarted = url.startAccessingSecurityScopedResource()
            guard securityScopedAccessStarted else {
                DebugLogger.error("无法开始安全访问文件")
                alertMessage = "无法访问选择的文件，请重试"
                showingAlert = true
                return
            }
            DebugLogger.success("成功开始安全访问文件")
        }

        // 检查文件属性（对 iCloud 文档需先开启安全访问）
        do {
            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .isReadableKey, .contentTypeKey])
            DebugLogger.info("文件大小: \(resourceValues.fileSize ?? 0) bytes")
            DebugLogger.info("文件可读: \(resourceValues.isReadable ?? false)")
            DebugLogger.info("文件类型: \(resourceValues.contentType?.identifier ?? "未知")")
        } catch {
            DebugLogger.error("获取文件属性失败: \(error.localizedDescription)")
        }

        Task {
            defer {
                if securityScopedAccessStarted {
                    DebugLogger.info("停止安全访问文件")
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                DebugLogger.info("开始导入书籍")
                let book = try await importService.importBook(from: url, context: viewContext)
                DebugLogger.success("书籍导入成功: \(book.displayTitle)")

                await MainActor.run {
                    importedBook = book
                    // 先关闭导入界面
                    DebugLogger.info("ImportBookView: 关闭导入界面")
                    dismiss()
                    // 延迟调用回调，确保sheet完全关闭
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        DebugLogger.info("ImportBookView: 调用 onBookImported 回调")
                        onBookImported?(book)
                    }
                }
            } catch {
                DebugLogger.error("书籍导入失败: \(error.localizedDescription)")
                DebugLogger.error("错误详情: \(error)")

                await MainActor.run {
                    alertMessage = error.localizedDescription
                    showingAlert = true
                }
            }
        }
    }
}


#Preview {
    LibraryView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
