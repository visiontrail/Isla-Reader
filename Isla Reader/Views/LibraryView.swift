//
//  LibraryView.swift
//  Isla Reader
//
//  Created by 郭亮 on 2025/9/10.
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \LibraryItem.lastAccessedAt, ascending: false)],
        animation: .default)
    private var libraryItems: FetchedResults<LibraryItem>
    
    // 强制刷新视图的状态
    @State private var refreshID = UUID()
    
    @State private var searchText = ""
    @State private var selectedFilter: ReadingStatus? = nil
    @State private var showingImportSheet = false
    @State private var showingFilterSheet = false
    @State private var bookToShowAISummary: Book? = nil
    @State private var bookForSkimming: Book? = nil
    @State private var bookForBookmarks: Book? = nil
    @State private var libraryItemForInfo: LibraryItem? = nil
    @State private var readerLaunchTarget: ReaderLaunchTarget? = nil
    
    private var filteredBooks: [LibraryItem] {
        var items = Array(libraryItems)
        
        // Apply search filter
        if !searchText.isEmpty {
            items = items.filter { item in
                item.book.title.localizedCaseInsensitiveContains(searchText) ||
                (item.book.author?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        // Apply status filter
        if let selectedFilter = selectedFilter {
            items = items.filter { $0.status == selectedFilter }
        }
        
        return items
    }
    
    private var columns: [GridItem] {
        let count = ResponsiveLayout.columns(for: horizontalSizeClass)
        let spacing = ResponsiveLayout.spacing(for: horizontalSizeClass)
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search and Filter Bar
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField(NSLocalizedString("搜索书籍或作者", comment: ""), text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    
                    Button(action: { showingFilterSheet = true }) {
                        Image(systemName: selectedFilter != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                // Content
                if filteredBooks.isEmpty {
                    EmptyLibraryView(showingImportSheet: $showingImportSheet)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(filteredBooks) { item in
                                BookCardView(libraryItem: item, onTap: {
                                    DebugLogger.info("LibraryView: 书籍卡片点击")
                                    DebugLogger.info("LibraryView: 点击的书籍 = \(item.book.displayTitle)")
                                    bookToShowAISummary = item.book
                                    DebugLogger.info("LibraryView: 设置 bookToShowAISummary")
                                }, onSkim: {
                                    DebugLogger.info("LibraryView: 进入略读模式 - \(item.book.displayTitle)")
                                    bookForSkimming = item.book
                                }, onShowBookmarks: {
                                    DebugLogger.info("LibraryView: 查看书签 - \(item.book.displayTitle)")
                                    bookForBookmarks = item.book
                                }, onShowInfo: {
                                    DebugLogger.info("LibraryView: 查看书籍信息 - \(item.book.displayTitle)")
                                    libraryItemForInfo = item
                                })
                            }
                        }
                        .padding()
                        .id(refreshID)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("我的书架", comment: ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingImportSheet = true }) {
                        Image(systemName: "plus")
                            .font(.title2)
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingImportSheet = true }) {
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
                        bookToShowAISummary = book
                        DebugLogger.info("LibraryView: 已设置 bookToShowAISummary = \(book.displayTitle)")
                    }
                })
            }
            .sheet(isPresented: $showingFilterSheet) {
                FilterSheetView(selectedFilter: $selectedFilter)
            }
            .fullScreenCover(item: $bookToShowAISummary) { book in
                NavigationView {
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
                NavigationView {
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
            .sheet(item: $libraryItemForInfo) { libraryItem in
                BookInfoSheet(libraryItem: libraryItem)
                    .environment(\.managedObjectContext, viewContext)
            }
            .fullScreenCover(item: $readerLaunchTarget) { target in
                NavigationView {
                    ReaderView(book: target.book, initialLocation: target.location)
                        .navigationBarHidden(true)
                }
                .environment(\.managedObjectContext, viewContext)
            }
            .onAppear {
                DebugLogger.info("LibraryView: 视图出现，刷新数据")
                refreshData()
            }
        }
    }
    
    // 刷新数据的辅助方法
    private func refreshData() {
        DebugLogger.info("LibraryView: 执行数据刷新")
        viewContext.refreshAllObjects()
        refreshID = UUID()
        DebugLogger.info("LibraryView: 数据刷新完成")
    }
}

struct BookCardView: View {
    let libraryItem: LibraryItem
    var onTap: (() -> Void)? = nil
    var onSkim: (() -> Void)? = nil
    var onShowBookmarks: (() -> Void)? = nil
    var onShowInfo: (() -> Void)? = nil
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
            
            // Progress Indicator and Status Badge
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
            }
            .padding(8)
        }
        .onTapGesture {
            onTap?()
        }
        .contextMenu {
            Button(action: { onSkim?() }) {
                Label(NSLocalizedString("略读模式", comment: ""), systemImage: "sparkles.rectangle.stack")
            }
            BookContextMenu(libraryItem: libraryItem, onShowBookmarks: onShowBookmarks, onShowInfo: onShowInfo)
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
    var onShowBookmarks: (() -> Void)? = nil
    var onShowInfo: (() -> Void)? = nil
    
    var body: some View {
        Button(action: {}) {
            Label(NSLocalizedString("继续阅读", comment: ""), systemImage: "book.open")
        }
        
        if let onShowBookmarks = onShowBookmarks {
            Button(action: onShowBookmarks) {
                Label(NSLocalizedString("bookmark.list.title", comment: ""), systemImage: "bookmark")
            }
        }
        
        Button(action: { onShowInfo?() }) {
            Label(NSLocalizedString("书籍信息", comment: ""), systemImage: "info.circle")
        }
        
        Button(action: {}) {
            Label(NSLocalizedString("添加到收藏", comment: ""), systemImage: "heart")
        }
        
        Divider()
        
        Button(role: .destructive, action: {}) {
            Label(NSLocalizedString("从书架移除", comment: ""), systemImage: "trash")
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
        NavigationView {
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
            .navigationTitle(NSLocalizedString("书籍信息", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("完成", comment: "")) {
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
    let location: BookmarkLocation
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
        NavigationView {
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
                    Button(NSLocalizedString("完成", comment: "")) {
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
                    .background(Color.primary.opacity(0.06))
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
}

struct EmptyLibraryView: View {
    @Binding var showingImportSheet: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "books.vertical")
                .font(.system(size: 80))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text(NSLocalizedString("书架空空如也", comment: ""))
                    .font(.title2)
                    .fontWeight(.medium)
                
                Text(NSLocalizedString("导入您的第一本电子书开始阅读之旅", comment: ""))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: { showingImportSheet = true }) {
                HStack {
                    Image(systemName: "plus")
                    Text(NSLocalizedString("导入书籍", comment: ""))
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
    @Binding var selectedFilter: ReadingStatus?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section(NSLocalizedString("阅读状态", comment: "")) {
                    Button(action: {
                        selectedFilter = nil
                        dismiss()
                    }) {
                        HStack {
                            Text(NSLocalizedString("全部", comment: ""))
                            Spacer()
                            if selectedFilter == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .foregroundColor(.primary)
                    
                    ForEach(ReadingStatus.allCases, id: \.rawValue) { status in
                        Button(action: {
                            selectedFilter = status
                            dismiss()
                        }) {
                            HStack {
                                Text(status.displayNameKey)
                                Spacer()
                                if selectedFilter == status {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("筛选", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
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
        NavigationView {
            VStack(spacing: 32) {
                Spacer()
                
                if importService.isImporting {
                    VStack(spacing: 16) {
                        ProgressView(value: importService.importProgress)
                            .progressViewStyle(LinearProgressViewStyle())
                            .frame(maxWidth: 200)
                        
                        Text(NSLocalizedString("正在导入书籍...", comment: ""))
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
                        Text(NSLocalizedString("导入电子书", comment: ""))
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text(NSLocalizedString("支持 ePub、TXT 等格式\n从文件 App 或其他应用导入", comment: ""))
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    VStack(spacing: 16) {
                        Button(action: { showingFilePicker = true }) {
                            HStack {
                                Image(systemName: "folder")
                                Text(NSLocalizedString("从文件 App 选择", comment: ""))
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .cornerRadius(12)
                        }
                        
                        Button(action: { showingFilePicker = true }) {
                            HStack {
                                Image(systemName: "icloud")
                                Text(NSLocalizedString("从 iCloud Drive 导入", comment: ""))
                            }
                            .font(.headline)
                            .foregroundColor(.accentColor)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle(NSLocalizedString("导入书籍", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("取消", comment: "")) {
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
            .alert(NSLocalizedString("导入结果", comment: ""), isPresented: $showingAlert) {
                Button(NSLocalizedString("确定", comment: "")) {
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
            
            DebugLogger.info("选择的文件URL: \(url.absoluteString)")
            DebugLogger.info("文件路径: \(url.path)")
            DebugLogger.info("文件扩展名: \(url.pathExtension)")
            
            // 检查文件属性
            do {
                let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .isReadableKey, .contentTypeKey])
                DebugLogger.info("文件大小: \(resourceValues.fileSize ?? 0) bytes")
                DebugLogger.info("文件可读: \(resourceValues.isReadable ?? false)")
                DebugLogger.info("文件类型: \(resourceValues.contentType?.identifier ?? "未知")")
            } catch {
                DebugLogger.error("获取文件属性失败: \(error.localizedDescription)")
            }
            
            // 开始安全访问文件
            DebugLogger.info("尝试开始安全访问文件")
            guard url.startAccessingSecurityScopedResource() else {
                DebugLogger.error("无法开始安全访问文件")
                alertMessage = "无法访问选择的文件，请重试"
                showingAlert = true
                return
            }
            DebugLogger.success("成功开始安全访问文件")
            
            Task {
                defer {
                    // 确保停止安全访问
                    DebugLogger.info("停止安全访问文件")
                    url.stopAccessingSecurityScopedResource()
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
            
        case .failure(let error):
            DebugLogger.error("文件选择失败: \(error.localizedDescription)")
            DebugLogger.error("错误详情: \(error)")
            alertMessage = "选择文件时出错：\(error.localizedDescription)"
            showingAlert = true
        }
    }
}


#Preview {
    LibraryView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
