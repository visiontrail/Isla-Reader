//
//  LibraryView.swift
//  Isla Reader
//
//  Created by 郭亮 on 2025/9/10.
//

import SwiftUI
import CoreData

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
                        TextField("搜索书籍或作者", text: $searchText)
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
                                BookCardView(libraryItem: item)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("我的书架")
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
                ImportBookView()
            }
            .sheet(isPresented: $showingFilterSheet) {
                FilterSheetView(selectedFilter: $selectedFilter)
            }
        }
    }
}

struct BookCardView: View {
    let libraryItem: LibraryItem
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private var cardWidth: CGFloat {
        ResponsiveLayout.cardWidth(for: horizontalSizeClass)
    }
    
    private var cardHeight: CGFloat {
        cardWidth * 1.4
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            
            // Book Info
            VStack(alignment: .leading, spacing: 4) {
                Text(libraryItem.book.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                Text(libraryItem.book.displayAuthor)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if libraryItem.hasRating {
                    Text(libraryItem.ratingStars)
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            .frame(width: cardWidth, alignment: .leading)
        }
        .onTapGesture {
            // Navigate to reader
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
            Label("继续阅读", systemImage: "book.open")
        }
        
        Button(action: {}) {
            Label("书籍信息", systemImage: "info.circle")
        }
        
        Button(action: {}) {
            Label("添加到收藏", systemImage: "heart")
        }
        
        Divider()
        
        Button(role: .destructive, action: {}) {
            Label("从书架移除", systemImage: "trash")
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
                Text("书架空空如也")
                    .font(.title2)
                    .fontWeight(.medium)
                
                Text("导入您的第一本电子书开始阅读之旅")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: { showingImportSheet = true }) {
                HStack {
                    Image(systemName: "plus")
                    Text("导入书籍")
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
                Section("阅读状态") {
                    Button(action: {
                        selectedFilter = nil
                        dismiss()
                    }) {
                        HStack {
                            Text("全部")
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
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ImportBookView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                Spacer()
                
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)
                
                VStack(spacing: 16) {
                    Text("导入电子书")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("支持 ePub、TXT 等格式\n从文件 App 或其他应用导入")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                VStack(spacing: 16) {
                    Button(action: {}) {
                        HStack {
                            Image(systemName: "folder")
                            Text("从文件 App 选择")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .cornerRadius(12)
                    }
                    
                    Button(action: {}) {
                        HStack {
                            Image(systemName: "icloud")
                            Text("从 iCloud Drive 导入")
                        }
                        .font(.headline)
                        .foregroundColor(.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("导入书籍")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    LibraryView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}