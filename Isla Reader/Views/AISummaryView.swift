//
//  AISummaryView.swift
//  Isla Reader
//
//  Created by AI Assistant on 2025/1/20.
//

import SwiftUI

struct AISummaryView: View {
    let book: Book
    @StateObject private var summaryService = AISummaryService.shared
    @State private var showingSummary = false
    @State private var isFirstOpen = true
    
    var body: some View {
        VStack(spacing: 0) {
            if showingSummary {
                summaryContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Text("加载中...")
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            DebugLogger.info("AISummaryView: onAppear触发")
            DebugLogger.info("AISummaryView: 书籍标题 = \(book.displayTitle)")
            DebugLogger.info("AISummaryView: isFirstOpen = \(isFirstOpen)")
            DebugLogger.info("AISummaryView: showingSummary = \(showingSummary)")
            
            if isFirstOpen {
                DebugLogger.info("AISummaryView: 首次打开，调用checkAndGenerateSummary")
                checkAndGenerateSummary()
                isFirstOpen = false
            } else {
                DebugLogger.info("AISummaryView: 非首次打开，跳过")
            }
        }
    }
    
    private var summaryContent: some View {
        VStack(spacing: 0) {
            // 摘要头部
            summaryHeader
            
            // 摘要内容
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    contentBodyView
                }
                .padding()
            }
            .background(Color(.systemBackground))
        }
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .padding()
    }
    
    @ViewBuilder
    private var contentBodyView: some View {
        if summaryService.isGenerating {
            generatingView
                .onAppear {
                    DebugLogger.info("AISummaryView: 显示生成中视图")
                }
        } else if !summaryService.currentSummary.isEmpty {
            summaryTextView
                .onAppear {
                    DebugLogger.info("AISummaryView: 显示摘要文本视图")
                }
        } else if let error = summaryService.error {
            errorView(error)
                .onAppear {
                    DebugLogger.error("AISummaryView: 显示错误视图 - \(error)")
                }
        } else {
            Text("没有可显示的内容")
                .foregroundColor(.secondary)
                .onAppear {
                    DebugLogger.warning("AISummaryView: 没有内容显示")
                }
        }
    }
    
    private var summaryHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.blue)
                        .font(.title2)
                    
                    Text("AI 导读摘要")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                Text("为您快速了解书籍内容")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                // 刷新按钮
                Button(action: refreshSummary) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .disabled(summaryService.isGenerating)
                
                // 收起按钮
                Button(action: { 
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingSummary = false
                    }
                }) {
                    Image(systemName: "chevron.up")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray5))
    }
    
    private var generatingView: some View {
        VStack(spacing: 16) {
            HStack {
                ProgressView(value: summaryService.generationProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                
                Text("\(Int(summaryService.generationProgress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 40)
            }
            
            if !summaryService.currentSummary.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("正在生成摘要...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(summaryService.currentSummary)
                        .font(.body)
                        .lineSpacing(4)
                        .animation(.easeInOut, value: summaryService.currentSummary)
                }
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(1.2)
                    
                    Text("正在分析书籍内容...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var summaryTextView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 主要摘要
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "doc.text")
                        .foregroundColor(.blue)
                    Text("内容摘要")
                        .font(.headline)
                        .fontWeight(.medium)
                }
                
                Text(summaryService.currentSummary)
                    .font(.body)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // 关键要点
            if let keyPointsString = book.aiKeyPoints,
               let keyPointsData = keyPointsString.data(using: .utf8),
               let keyPoints = try? JSONDecoder().decode([String].self, from: keyPointsData),
               !keyPoints.isEmpty {
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "list.bullet")
                            .foregroundColor(.orange)
                        Text("关键要点")
                            .font(.headline)
                            .fontWeight(.medium)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(keyPoints.enumerated()), id: \.offset) { index, point in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .foregroundColor(.orange)
                                    .fontWeight(.bold)
                                
                                Text(point)
                                    .font(.body)
                                    .lineSpacing(4)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                Spacer()
                            }
                        }
                    }
                }
            }
            
            // 生成时间
            if let generatedAt = book.aiSummaryGeneratedAt {
                HStack {
                    Spacer()
                    Text("生成于 \(formatDate(generatedAt))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            
            Text("生成摘要时出错")
                .font(.headline)
                .fontWeight(.medium)
            
            Text(error)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: refreshSummary) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("重试")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.blue)
                .cornerRadius(8)
            }
        }
        .padding()
    }
    
    private func checkAndGenerateSummary() {
        DebugLogger.info("AISummaryView: checkAndGenerateSummary 开始")
        
        // 检查是否已有摘要
        let hasAISummary = book.aiSummary != nil
        let hasGeneratedAt = book.aiSummaryGeneratedAt != nil
        
        DebugLogger.info("AISummaryView: hasAISummary = \(hasAISummary)")
        DebugLogger.info("AISummaryView: hasGeneratedAt = \(hasGeneratedAt)")
        
        if hasAISummary && hasGeneratedAt {
            DebugLogger.success("AISummaryView: 书籍已有摘要，直接显示")
            summaryService.currentSummary = book.aiSummary ?? ""
            DebugLogger.info("AISummaryView: 摘要内容长度 = \(summaryService.currentSummary.count)")
            
            withAnimation(.easeInOut(duration: 0.5).delay(1.0)) {
                DebugLogger.info("AISummaryView: 设置 showingSummary = true")
                showingSummary = true
            }
        } else {
            // 首次打开，生成摘要
            DebugLogger.info("AISummaryView: 书籍没有摘要，准备生成")
            generateSummaryWithStream()
        }
    }
    
    private func generateSummaryWithStream() {
        DebugLogger.info("AISummaryView: generateSummaryWithStream 开始")
        
        withAnimation(.easeInOut(duration: 0.3)) {
            DebugLogger.info("AISummaryView: 显示摘要容器")
            showingSummary = true
        }
        
        Task {
            do {
                DebugLogger.info("AISummaryView: 开始调用 summaryService.generateSummaryStream")
                for try await partialSummary in summaryService.generateSummaryStream(for: book) {
                    DebugLogger.info("AISummaryView: 收到部分摘要，长度 = \(partialSummary.count)")
                    // 流式输出已在service中处理
                }
                DebugLogger.success("AISummaryView: 摘要生成完成")
            } catch {
                DebugLogger.error("AISummaryView: 生成摘要失败 - \(error.localizedDescription)")
                DebugLogger.error("AISummaryView: 错误详情 - \(error)")
            }
        }
    }
    
    private func refreshSummary() {
        DebugLogger.info("AISummaryView: refreshSummary 触发")
        
        // 清除当前摘要
        summaryService.currentSummary = ""
        book.aiSummary = nil
        book.aiKeyPoints = nil
        book.aiSummaryGeneratedAt = nil
        
        DebugLogger.info("AISummaryView: 已清除旧摘要，准备重新生成")
        
        // 重新生成
        generateSummaryWithStream()
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}

// 可展开的摘要卡片组件
struct AISummaryCard: View {
    let book: Book
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 卡片头部
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.blue)
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI 导读摘要")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        if book.aiSummary != nil {
                            Text("点击查看详细摘要")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("点击生成摘要")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
            
            // 展开的摘要内容
            if isExpanded {
                AISummaryView(book: book)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

#Preview {
    let book = Book()
    book.title = "示例书籍"
    book.author = "示例作者"
    return AISummaryView(book: book)
        .padding()
}