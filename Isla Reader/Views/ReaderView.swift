//
//  ReaderView.swift
//  Isla Reader
//
//  Created by 郭亮 on 2025/9/10.
//

import SwiftUI
import CoreData

struct Page: Identifiable, Equatable {
    let id = UUID()
    let chapterIndex: Int
    let pageIndex: Int
    let content: String
    let chapterTitle: String
    let isFirstPageOfChapter: Bool
}

struct ReaderView: View {
    let book: Book
    @StateObject private var appSettings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var chapters: [Chapter] = []
    @State private var pages: [Page] = []
    @State private var currentPageIndex = 0
    @State private var currentChapterIndex = 0
    @State private var isLoading = true
    @State private var loadError: String?
    
    @State private var showingToolbar = false
    @State private var showingTableOfContents = false
    @State private var showingAIChat = false
    @State private var showingSettings = false
    @State private var selectedText = ""
    @State private var showingTextActions = false
    @State private var showingAISummary = false
    @State private var isFirstOpen = true
    
    @State private var scrollOffset: CGFloat = 0
    @State private var lastTapTime: Date = Date()
    @State private var viewSize: CGSize = .zero
    
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
                chapters: chapters,
                currentChapterIndex: $currentChapterIndex,
                pages: pages,
                onChapterSelected: { chapterIndex in
                    // Find first page of selected chapter
                    if let firstPageIndex = pages.firstIndex(where: { $0.chapterIndex == chapterIndex }) {
                        currentPageIndex = firstPageIndex
                    }
                }
            )
        }
        .sheet(isPresented: $showingSettings) {
            ReaderSettingsView(onSettingsChanged: {
                // Re-paginate content when settings change
                if !chapters.isEmpty && viewSize != .zero {
                    paginateContent()
                }
            })
        }
        .sheet(isPresented: $showingAIChat) {
            if horizontalSizeClass == .compact {
                AIChatView(book: book)
            }
        }
        .sheet(isPresented: $showingTextActions) {
            TextActionsView(selectedText: selectedText)
        }
        .onAppear {
            loadBookContent()
            checkFirstTimeOpen()
        }
        .onChange(of: viewSize) { _ in
            if !chapters.isEmpty && viewSize != .zero {
                paginateContent()
            }
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
            // Reading content with page turning
            GeometryReader { geometry in
                TabView(selection: $currentPageIndex) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        pageView(page: page, geometry: geometry)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onChange(of: currentPageIndex) { newValue in
                    if !pages.isEmpty && newValue < pages.count {
                        currentChapterIndex = pages[newValue].chapterIndex
                        saveReadingProgress()
                    }
                }
                .background(
                    GeometryReader { geo in
                        Color.clear.onAppear {
                            viewSize = geo.size
                        }
                        .onChange(of: geo.size) { newSize in
                            if viewSize != newSize {
                                viewSize = newSize
                            }
                        }
                    }
                )
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
    
    private func pageView(page: Page, geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // AI Summary card for first page
            if showingAISummary && isFirstOpen && page.chapterIndex == 0 && page.pageIndex == 0 {
                AISummaryCard(book: book)
                    .padding(.horizontal, horizontalPadding(for: geometry))
                    .padding(.top, 60)
                    .padding(.bottom, 24)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Chapter title on first page of chapter
            if page.isFirstPageOfChapter {
                Text(page.chapterTitle)
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .foregroundColor(.primary.opacity(0.95))
                    .padding(.horizontal, horizontalPadding(for: geometry))
                    .padding(.top, (showingAISummary && isFirstOpen && page.chapterIndex == 0 && page.pageIndex == 0) ? 0 : 80)
                    .padding(.bottom, 28)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Page content with beautiful typography
            Text(page.content)
                .font(.system(size: appSettings.readingFontSize.fontSize, design: .serif))
                .lineSpacing(appSettings.lineSpacing * 8)
                .foregroundColor(.primary.opacity(0.87))
                .kerning(0.3)
                .padding(.horizontal, horizontalPadding(for: geometry))
                .padding(.top, page.isFirstPageOfChapter ? 0 : 80)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            
            Spacer()
            
            // Page number at bottom
            HStack {
                Spacer()
                Text("\(currentPageIndex + 1) / \(pages.count)")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.6))
                Spacer()
            }
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap()
        }
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
            Button(action: { dismiss() }) {
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
            // Reading progress indicator
            if !pages.isEmpty {
                HStack(spacing: 8) {
                    Text("\(currentPageIndex + 1)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .frame(minWidth: 36)
                    
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
                                .frame(width: geometry.size.width * CGFloat(currentPageIndex + 1) / CGFloat(pages.count), height: 4)
                        }
                    }
                    .frame(height: 4)
                    
                    Text("\(pages.count)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .frame(minWidth: 36)
                }
                .padding(.horizontal, 20)
            }
            
            // Action buttons
            HStack(spacing: 0) {
                toolbarButton(icon: "bookmark", action: {})
                toolbarButton(icon: "highlighter", action: { showingTextActions = true })
                toolbarButton(icon: "message.fill", action: { showingAIChat = true })
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
    
    private func toolbarButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
    }
    
    // MARK: - Helper Methods
    
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
                // Get the book file path
                let fileURL = URL(fileURLWithPath: book.filePath)
                
                // Parse EPUB
                let metadata = try EPubParser.parseEPub(from: fileURL)
                
                DispatchQueue.main.async {
                    self.chapters = metadata.chapters
                    
                    // Paginate content after loading
                    if self.viewSize != .zero {
                        self.paginateContent()
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
    
    private func paginateContent() {
        guard !chapters.isEmpty, viewSize != .zero else { return }
        
        var allPages: [Page] = []
        let availableHeight = viewSize.height - 200 // Account for top/bottom padding and toolbar
        let horizontalPadding = calculateHorizontalPadding()
        let availableWidth = viewSize.width - (horizontalPadding * 2)
        
        // Calculate approximate characters per page
        let fontSize = appSettings.readingFontSize.fontSize
        let lineSpacing = appSettings.lineSpacing * 8
        let lineHeight = fontSize + lineSpacing
        let linesPerPage = Int(availableHeight / lineHeight)
        let charsPerLine = Int(availableWidth / (fontSize * 0.5)) // Approximate
        let charsPerPage = linesPerPage * charsPerLine
        
        for (chapterIndex, chapter) in chapters.enumerated() {
            let content = chapter.content
            let contentLength = content.count
            
            if contentLength <= charsPerPage {
                // Single page chapter
                allPages.append(Page(
                    chapterIndex: chapterIndex,
                    pageIndex: 0,
                    content: content,
                    chapterTitle: chapter.title,
                    isFirstPageOfChapter: true
                ))
            } else {
                // Multi-page chapter
                var pageIndex = 0
                var startIndex = content.startIndex
                
                while startIndex < content.endIndex {
                    let remainingLength = content.distance(from: startIndex, to: content.endIndex)
                    let pageLength = min(charsPerPage, remainingLength)
                    
                    var endIndex = content.index(startIndex, offsetBy: pageLength)
                    
                    // Try to break at paragraph or sentence
                    if endIndex < content.endIndex {
                        let searchRange = content.index(endIndex, offsetBy: -min(200, pageLength))...endIndex
                        if let paragraphBreak = content[searchRange].lastIndex(of: "\n") {
                            endIndex = paragraphBreak
                        } else if let sentenceBreak = content[searchRange].lastIndex(where: { "。！？.!?".contains($0) }) {
                            endIndex = content.index(after: sentenceBreak)
                        }
                    }
                    
                    let pageContent = String(content[startIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    allPages.append(Page(
                        chapterIndex: chapterIndex,
                        pageIndex: pageIndex,
                        content: pageContent,
                        chapterTitle: chapter.title,
                        isFirstPageOfChapter: pageIndex == 0
                    ))
                    
                    startIndex = endIndex
                    pageIndex += 1
                }
            }
        }
        
        pages = allPages
        
        // Restore reading progress
        if let progress = book.readingProgress {
            let savedPage = Int(progress.currentPage)
            if savedPage < pages.count {
                currentPageIndex = savedPage
                if !pages.isEmpty {
                    currentChapterIndex = pages[savedPage].chapterIndex
                }
            }
        }
    }
    
    private func calculateHorizontalPadding() -> CGFloat {
        let width = viewSize.width
        if width > 1000 {
            return width * 0.20 // Large iPad
        } else if width > 700 {
            return width * 0.15 // iPad
        } else {
            return max(appSettings.pageMargins, 24) // iPhone
        }
    }
    
    private func saveReadingProgress() {
        guard !pages.isEmpty else { return }
        
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
            progress.currentPage = Int32(currentPageIndex)
            progress.progressPercentage = Double(currentPageIndex + 1) / Double(pages.count)
            progress.lastReadAt = Date()
            progress.updatedAt = Date()
            
            // Update book's totalPages if needed
            if book.totalPages != Int32(pages.count) {
                book.totalPages = Int32(pages.count)
            }
            
            try? viewContext.save()
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
 }


struct TableOfContentsView: View {
    let chapters: [Chapter]
    @Binding var currentChapterIndex: Int
    let pages: [Page]
    let onChapterSelected: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(chapters.enumerated()), id: \.element.order) { index, chapter in
                        Button(action: {
                            onChapterSelected(index)
                            dismiss()
                        }) {
                            HStack(spacing: 12) {
                                // Chapter number indicator
                                ZStack {
                                    Circle()
                                        .fill(index == currentChapterIndex ? 
                                              LinearGradient(gradient: Gradient(colors: [.blue, .blue.opacity(0.7)]), 
                                                           startPoint: .topLeading, 
                                                           endPoint: .bottomTrailing) :
                                              LinearGradient(gradient: Gradient(colors: [.gray.opacity(0.2), .gray.opacity(0.1)]), 
                                                           startPoint: .topLeading, 
                                                           endPoint: .bottomTrailing))
                                        .frame(width: 36, height: 36)
                                    
                                    Text("\(index + 1)")
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundColor(index == currentChapterIndex ? .white : .secondary)
                                }
                                
                                // Chapter title
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(chapter.title)
                                        .font(.system(size: 16, weight: .medium, design: .serif))
                                        .foregroundColor(.primary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    
                                    if index == currentChapterIndex {
                                        Text(NSLocalizedString("当前章节", comment: ""))
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundColor(.blue)
                                    }
                                }
                                
                                Spacer()
                                
                                if index == currentChapterIndex {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .id(index)
                    }
                }
                .listStyle(.insetGrouped)
                .onAppear {
                    // Scroll to current chapter
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            proxy.scrollTo(currentChapterIndex, anchor: .center)
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("目录", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
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
}

struct ReaderSettingsView: View {
    @StateObject private var appSettings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    let onSettingsChanged: () -> Void
    
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("完成", comment: "")) {
                        dismiss()
                    }
                }
            }
            .onChange(of: appSettings.readingFontSize) { _ in
                onSettingsChanged()
            }
            .onChange(of: appSettings.lineSpacing) { _ in
                onSettingsChanged()
            }
            .onChange(of: appSettings.pageMargins) { _ in
                onSettingsChanged()
            }
        }
    }
}

struct AIChatSidebar: View {
    let book: Book
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(NSLocalizedString("AI 阅读助手", comment: ""))
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: {}) {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            
            // Messages
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "message.circle")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            
                            Text(NSLocalizedString("向 AI 提问关于这本书的任何问题", comment: ""))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text(NSLocalizedString("建议问题:", comment: ""))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                
                                SuggestedQuestionButton(question: NSLocalizedString("这章的主要内容是什么？", comment: ""))
                                SuggestedQuestionButton(question: NSLocalizedString("解释一下这个概念", comment: ""))
                                SuggestedQuestionButton(question: NSLocalizedString("总结一下要点", comment: ""))
                            }
                        }
                        .padding()
                    } else {
                        ForEach(messages) { message in
                            ChatMessageView(message: message)
                        }
                    }
                }
                .padding()
            }
            
            // Input
            HStack {
                TextField(NSLocalizedString("向 AI 提问...", comment: ""), text: $inputText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.blue)
                }
                .disabled(inputText.isEmpty)
            }
            .padding()
        }
        .background(Color(.systemBackground))
    }
    
    private func sendMessage() {
        guard !inputText.isEmpty else { return }
        
        let userMessage = ChatMessage(content: inputText, isUser: true)
        messages.append(userMessage)
        
        let question = inputText
        inputText = ""
        
        // Simulate AI response
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let aiResponse = ChatMessage(content: "这是一个关于 \"\(question)\" 的AI回答。在实际应用中，这里会显示真实的AI分析和回答。", isUser: false)
            messages.append(aiResponse)
        }
    }
}

struct SuggestedQuestionButton: View {
    let question: String
    
    var body: some View {
        Button(action: {}) {
            Text(question)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.systemGray5))
                .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct AIChatView: View {
    let book: Book
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            AIChatSidebar(book: book)
                .navigationTitle(NSLocalizedString("AI 阅读助手", comment: ""))
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

struct ChatMessage: Identifiable {
    let id = UUID()
    let content: String
    let isUser: Bool
    let timestamp = Date()
}

struct ChatMessageView: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(message.content)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                    
                    Text(formatTime(message.timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity * 0.8, alignment: .trailing)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.content)
                        .padding()
                        .background(Color(.systemGray5))
                        .cornerRadius(16)
                    
                    Text(formatTime(message.timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity * 0.8, alignment: .leading)
                
                Spacer()
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
                    .background(Color(.systemGray6))
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
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    ReaderView(book: Book())
}