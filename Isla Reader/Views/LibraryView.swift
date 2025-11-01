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
    
    @State private var searchText = ""
    @State private var selectedFilter: ReadingStatus? = nil
    @State private var showingImportSheet = false
    @State private var showingFilterSheet = false
    @State private var bookToShowAISummary: Book? = nil
    
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
                                })
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(NSLocalizedString("我的书架", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingImportSheet = true }) {
                        Image(systemName: "plus")
                            .font(.title2)
                    }
                }
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
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button(action: {
                                    DebugLogger.info("LibraryView: 关闭按钮点击，关闭AI摘要界面")
                                    bookToShowAISummary = nil
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
        }
    }
}

struct BookCardView: View {
    let libraryItem: LibraryItem
    var onTap: (() -> Void)? = nil
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
            
            // Status Badge
            VStack {
                HStack {
                    Spacer()
                    StatusBadge(status: libraryItem.status)
                }
                Spacer()
            }
            .padding(8)
            
            // Progress Indicator
            if libraryItem.status == .reading,
               let progress = libraryItem.book.readingProgress {
                VStack {
                    Spacer()
                    ProgressBar(progress: progress.progressPercentage)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }
            }
        }
        .onTapGesture {
            onTap?()
        }
        .contextMenu {
            BookContextMenu(libraryItem: libraryItem)
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
    
    var body: some View {
        Button(action: {}) {
            Label(NSLocalizedString("继续阅读", comment: ""), systemImage: "book.open")
        }
        
        Button(action: {}) {
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("完成", comment: "")) {
                        dismiss()
                    }
                }
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