//
//  ReaderView.swift
//  Isla Reader
//
//  Created by 郭亮 on 2025/9/10.
//

import SwiftUI

struct ReaderView: View {
    let book: Book
    @StateObject private var appSettings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    @State private var currentPage = 0
    @State private var totalPages = 100
    @State private var showingToolbar = true
    @State private var showingTableOfContents = false
    @State private var showingAIChat = false
    @State private var showingSettings = false
    @State private var selectedText = ""
    @State private var showingTextActions = false
    
    // Sample content for demonstration
    private let sampleContent = """
    第一章 开始的地方

    在一个阳光明媚的早晨，主人公踏上了一段全新的旅程。这是一个关于成长、发现和自我实现的故事。

    每个人的生命中都有那么一些时刻，它们如同夜空中最亮的星，指引着我们前进的方向。对于我们的主人公来说，这个早晨就是这样的时刻。

    窗外的阳光透过薄薄的窗帘洒进房间，在地板上投下斑驳的光影。空气中弥漫着淡淡的花香，那是从花园里飘来的茉莉花的味道。

    这是一个充满希望的开始，也是一个充满挑战的开始。但正如古人所说："千里之行，始于足下。"无论前路如何，重要的是迈出第一步。

    在接下来的章节中，我们将跟随主人公一起经历这段奇妙的旅程，见证他的成长和蜕变。
    """
    
    var body: some View {
        ZStack {
            // Background
            Color(.systemBackground)
                .ignoresSafeArea()
            
            // Main Content
            VStack(spacing: 0) {
                // Top Toolbar
                if showingToolbar {
                    ReaderTopToolbar(
                        bookTitle: book.displayTitle,
                        currentPage: currentPage,
                        totalPages: totalPages,
                        onBack: { dismiss() },
                        onTableOfContents: { showingTableOfContents = true },
                        onSettings: { showingSettings = true }
                    )
                    .transition(.move(edge: .top))
                }
                
                // Reading Content
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        // Main Text Area
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(sampleContent)
                                    .font(.system(size: appSettings.readingFontSize.fontSize))
                                    .lineSpacing(appSettings.lineSpacing * 4)
                                    .padding(.horizontal, appSettings.pageMargins)
                                    .padding(.vertical, 20)
                                    .textSelection(.enabled)
                                    .onTapGesture {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            showingToolbar.toggle()
                                        }
                                    }
                            }
                        }
                        .frame(maxWidth: horizontalSizeClass == .regular && showingAIChat ? geometry.size.width * 0.6 : .infinity)
                        
                        // AI Chat Sidebar (iPad only)
                        if horizontalSizeClass == .regular && showingAIChat {
                            Divider()
                            
                            AIChatSidebar(book: book)
                                .frame(width: geometry.size.width * 0.4)
                                .transition(.move(edge: .trailing))
                        }
                    }
                }
                
                // Bottom Toolbar
                if showingToolbar {
                    ReaderBottomToolbar(
                        currentPage: $currentPage,
                        totalPages: totalPages,
                        onBookmark: {},
                        onHighlight: { showingTextActions = true },
                        onAIChat: { 
                            if horizontalSizeClass == .regular {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showingAIChat.toggle()
                                }
                            } else {
                                showingAIChat = true
                            }
                        },
                        onShare: {}
                    )
                    .transition(.move(edge: .bottom))
                }
            }
        }
        .navigationBarHidden(true)
        .preferredColorScheme(appSettings.theme.colorScheme)
        .sheet(isPresented: $showingTableOfContents) {
            TableOfContentsView(book: book)
        }
        .sheet(isPresented: $showingSettings) {
            ReaderSettingsView()
        }
        .sheet(isPresented: $showingAIChat) {
            if horizontalSizeClass == .compact {
                AIChatView(book: book)
            }
        }
        .sheet(isPresented: $showingTextActions) {
            TextActionsView(selectedText: selectedText)
        }
        .animation(.easeInOut(duration: 0.3), value: showingToolbar)
        .animation(.easeInOut(duration: 0.3), value: showingAIChat)
    }
}

struct ReaderTopToolbar: View {
    let bookTitle: String
    let currentPage: Int
    let totalPages: Int
    let onBack: () -> Void
    let onTableOfContents: () -> Void
    let onSettings: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.primary)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(bookTitle)
                    .font(.headline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Text("第 \(currentPage) 页 / 共 \(totalPages) 页")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                Button(action: onTableOfContents) {
                    Image(systemName: "list.bullet")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
                
                Button(action: onSettings) {
                    Image(systemName: "textformat")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.systemBackground).opacity(0.95))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(.separator)),
            alignment: .bottom
        )
    }
}

struct ReaderBottomToolbar: View {
    @Binding var currentPage: Int
    let totalPages: Int
    let onBookmark: () -> Void
    let onHighlight: () -> Void
    let onAIChat: () -> Void
    let onShare: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Progress Slider
            HStack {
                Text("\(currentPage)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 30)
                
                Slider(value: Binding(
                    get: { Double(currentPage) },
                    set: { currentPage = Int($0) }
                ), in: 1...Double(totalPages), step: 1)
                .accentColor(.blue)
                
                Text("\(totalPages)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 30)
            }
            .padding(.horizontal)
            
            // Action Buttons
            HStack(spacing: 0) {
                ToolbarButton(icon: "bookmark", action: onBookmark)
                ToolbarButton(icon: "highlighter", action: onHighlight)
                ToolbarButton(icon: "message", action: onAIChat)
                ToolbarButton(icon: "square.and.arrow.up", action: onShare)
            }
        }
        .padding(.vertical, 12)
        .background(Color(.systemBackground).opacity(0.95))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(.separator)),
            alignment: .top
        )
    }
}

struct ToolbarButton: View {
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
    }
}

struct TableOfContentsView: View {
    let book: Book
    @Environment(\.dismiss) private var dismiss
    
    // Sample table of contents
    private let chapters = [
        ("第一章", "开始的地方", 1),
        ("第二章", "初次相遇", 15),
        ("第三章", "意外的发现", 28),
        ("第四章", "深入探索", 42),
        ("第五章", "转折点", 56),
        ("第六章", "新的理解", 71),
        ("第七章", "挑战与成长", 85),
        ("第八章", "最终的答案", 98)
    ]
    
    var body: some View {
        NavigationView {
            List {
                ForEach(Array(chapters.enumerated()), id: \.offset) { index, chapter in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(chapter.0)
                                .font(.headline)
                                .fontWeight(.medium)
                            
                            Text(chapter.1)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text("第 \(chapter.2) 页")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Navigate to chapter
                        dismiss()
                    }
                }
            }
            .navigationTitle("目录")
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

struct ReaderSettingsView: View {
    @StateObject private var appSettings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("字体设置") {
                    HStack {
                        Text("字体大小")
                        Spacer()
                        Picker("字体大小", selection: $appSettings.readingFontSize) {
                            ForEach(ReadingFontSize.allCases, id: \.rawValue) { size in
                                Text(size.displayName).tag(size)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                }
                
                Section("排版设置") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("行间距")
                            Spacer()
                            Text(String(format: "%.1f", appSettings.lineSpacing))
                                .foregroundColor(.secondary)
                        }
                        
                        Slider(value: $appSettings.lineSpacing, in: 1.0...2.0, step: 0.1)
                            .accentColor(.blue)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("页面边距")
                            Spacer()
                            Text("\(Int(appSettings.pageMargins))pt")
                                .foregroundColor(.secondary)
                        }
                        
                        Slider(value: $appSettings.pageMargins, in: 10...40, step: 5)
                            .accentColor(.blue)
                    }
                }
                
                Section("主题") {
                    Picker("主题", selection: $appSettings.theme) {
                        ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
            }
            .navigationTitle("阅读设置")
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

struct AIChatSidebar: View {
    let book: Book
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("AI 阅读助手")
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
                            
                            Text("向 AI 提问关于这本书的任何问题")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("建议问题:")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                
                                SuggestedQuestionButton(question: "这章的主要内容是什么？")
                                SuggestedQuestionButton(question: "解释一下这个概念")
                                SuggestedQuestionButton(question: "总结一下要点")
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
                TextField("向 AI 提问...", text: $inputText)
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
                .navigationTitle("AI 阅读助手")
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
                Text("选中文本")
                    .font(.headline)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                
                VStack(spacing: 16) {
                    ActionButton(title: "高亮标记", icon: "highlighter", color: .yellow) {}
                    ActionButton(title: "添加笔记", icon: "note.text", color: .blue) {}
                    ActionButton(title: "翻译", icon: "globe", color: .green) {}
                    ActionButton(title: "AI 解释", icon: "brain.head.profile", color: .purple) {}
                    ActionButton(title: "复制", icon: "doc.on.doc", color: .gray) {}
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("文本操作")
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