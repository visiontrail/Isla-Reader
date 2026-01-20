//
//  SkimmingModeView.swift
//  LanRead
//
//  Created by AI Assistant on 2025/1/22.
//

import SwiftUI

struct SkimmingModeView: View {
    let book: Book
    
    @StateObject private var appSettings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    @State private var chapters: [SkimmingChapterMetadata] = []
    @State private var isLoadingChapters = true
    @State private var loadError: String?
    @State private var currentChapterIndex = 0
    @State private var chapterSummaries: [Int: SkimmingChapterSummary] = [:]
    @State private var loadingChapterIndices: Set<Int> = []
    @State private var chapterErrors: [Int: String] = [:]
    @State private var showingTOC = false
    @State private var navigationPath = NavigationPath()
    @State private var skimmingAIRequestCount = 0
    
    private let service = SkimmingModeService.shared
    
    private enum NavigationTarget: Hashable {
        case startFromChapter(BookmarkLocation)
        case resume
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                backgroundView
                    .ignoresSafeArea()
                
                if isLoadingChapters {
                    ProgressView(NSLocalizedString("skimming.loading_chapters", comment: ""))
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else if let loadError {
                    errorView(loadError, retry: loadChapters)
                } else {
                    contentView
                }
            }
            .preferredColorScheme(appSettings.theme.colorScheme)
            .onAppear {
                loadChapters()
                RewardedInterstitialAdManager.shared.loadAd()
            }
            .sheet(isPresented: $showingTOC) {
                SkimmingTableOfContentsView(
                    chapters: chapters,
                    currentChapterIndex: $currentChapterIndex,
                    summaries: chapterSummaries
                )
            }
            .navigationBarHidden(true)
            .navigationDestination(for: NavigationTarget.self) { destination in
                switch destination {
                case .startFromChapter(let location):
                    ReaderView(book: book, initialLocation: location)
                        .navigationBarHidden(true)
                case .resume:
                    ReaderView(book: book)
                        .navigationBarHidden(true)
                }
            }
        }
    }
    
    private var contentView: some View {
        VStack(spacing: 0) {
            topBar
            
            if chapters.isEmpty {
                emptyChaptersView
            } else {
                chapterPager
            }
            
            bottomProgress
        }
        .padding(.top, 12)
        .padding(.horizontal)
    }
    
    private var backgroundView: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.04, green: 0.05, blue: 0.1),
                Color(red: 0.02, green: 0.02, blue: 0.05)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private var topBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.9))
                }
                
                Spacer()
                
                Button(action: { showingTOC = true }) {
                    Label(NSLocalizedString("目录", comment: ""), systemImage: "list.bullet")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(book.displayTitle)
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    modeBadge
                    Text(NSLocalizedString("skimming.subtitle", comment: ""))
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
    }
    
    private var modeBadge: some View {
        Text(NSLocalizedString("skimming.mode_badge", comment: ""))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.15))
            .foregroundColor(.white)
            .cornerRadius(8)
    }
    
    private var chapterPager: some View {
        TabView(selection: $currentChapterIndex) {
            ForEach(chapters.indices, id: \.self) { index in
                SkimmingChapterPage(
                    chapter: chapters[index],
                    summary: chapterSummaries[index],
                    isLoading: loadingChapterIndices.contains(index),
                    error: chapterErrors[index],
                    onRequestSummary: { requestSummary(for: index) },
                    onStartFullReading: { openReader(at: index) }
                )
                .padding(.vertical, 20)
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: currentChapterIndex) { newValue in
            guard chapters.indices.contains(newValue) else { return }
            service.storeLastVisitedChapterIndex(newValue, for: book)
            requestSummary(for: newValue)
        }
    }
    
    private var bottomProgress: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(currentChapterIndex + 1)/\(max(chapters.count, 1))")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Button(action: resumeFullReading) {
                    Label(NSLocalizedString("skimming.switch_to_full", comment: ""), systemImage: "book.closed")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(20)
                }
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 4)
                    Capsule()
                        .fill(Color.white)
                        .frame(width: geometry.size.width * progressRatio, height: 4)
                }
            }
            .frame(height: 6)
        }
        .padding(.bottom, 16)
    }
    
    private var progressRatio: CGFloat {
        guard !chapters.isEmpty else { return 0 }
        return CGFloat(currentChapterIndex + 1) / CGFloat(chapters.count)
    }
    
    private func openReader(at index: Int) {
        guard chapters.indices.contains(index) else { return }
        let chapter = chapters[index]
        let location = BookmarkLocation(
            chapterIndex: index,
            pageIndex: 0,
            chapterTitle: chapter.title
        )
        navigationPath.append(NavigationTarget.startFromChapter(location))
    }
    
    private func resumeFullReading() {
        navigationPath.append(NavigationTarget.resume)
    }
    
    private func initialChapterIndex(for totalCount: Int) -> Int {
        guard totalCount > 0 else { return 0 }
        let storedIndex = service.lastVisitedChapterIndex(for: book) ?? 0
        return min(max(storedIndex, 0), totalCount - 1)
    }
    
    private var emptyChaptersView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44))
                .foregroundColor(.white.opacity(0.6))
            Text(NSLocalizedString("skimming.no_chapters", comment: ""))
                .foregroundColor(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func loadChapters() {
        isLoadingChapters = true
        loadError = nil
        Task {
            do {
                let metadata = try service.chapters(from: book)
                await MainActor.run {
                    let previousIndex = self.currentChapterIndex
                    self.chapters = metadata
                    self.isLoadingChapters = false
                    let restoredIndex = self.initialChapterIndex(for: metadata.count)
                    self.currentChapterIndex = restoredIndex
                    // 从缓存中恢复已生成的摘要
                    self.restoreCachedSummaries()
                    if previousIndex == restoredIndex {
                        self.requestSummary(for: restoredIndex)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoadingChapters = false
                    self.loadError = error.localizedDescription
                }
            }
        }
    }
    
    private func restoreCachedSummaries() {
        for (index, chapter) in chapters.enumerated() {
            if let cachedSummary = service.cachedSummary(for: book, chapter: chapter) {
                chapterSummaries[index] = cachedSummary
            }
        }
    }
    
    @MainActor
    private func requestSummary(for index: Int) {
        guard chapters.indices.contains(index) else { return }
        if chapterSummaries[index] != nil || loadingChapterIndices.contains(index) {
            return
        }
        loadingChapterIndices.insert(index)
        chapterErrors[index] = nil
        let chapter = chapters[index]
        Task {
            do {
                let summary = try await service.generateSkimmingSummary(for: book, chapter: chapter)
                await MainActor.run {
                    self.chapterSummaries[index] = summary
                    self.loadingChapterIndices.remove(index)
                    incrementSkimmingUsageAndShowAdIfNeeded()
                }
            } catch {
                await MainActor.run {
                    self.loadingChapterIndices.remove(index)
                    self.chapterErrors[index] = error.localizedDescription
                }
            }
        }
    }
    
    private func errorView(_ message: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundColor(.yellow)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
            Button(action: retry) {
                Text(NSLocalizedString("skimming.retry", comment: ""))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(12)
            }
        }
        .padding()
    }
    
    @MainActor
    private func incrementSkimmingUsageAndShowAdIfNeeded() {
        skimmingAIRequestCount += 1
        DebugLogger.info("SkimmingModeView: 略读AI调用计数 = \(skimmingAIRequestCount)")
        
        guard skimmingAIRequestCount.isMultiple(of: 3) else { return }
        DebugLogger.info("SkimmingModeView: 达到展示奖励插页式广告的阈值")
        RewardedInterstitialAdManager.shared.presentFromTopControllerIfAvailable()
    }
}

private struct SkimmingChapterPage: View {
    let chapter: SkimmingChapterMetadata
    let summary: SkimmingChapterSummary?
    let isLoading: Bool
    let error: String?
    let onRequestSummary: () -> Void
    let onStartFullReading: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(chapter.title)
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                
                if isLoading {
                    loadingSection
                } else if let error {
                    chapterErrorView(error)
                } else if let summary {
                    summarySections(summary)
                } else {
                    placeholderView
                }
            }
            .padding(24)
            .background(.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .scrollIndicators(.hidden)
    }
    
    private var loadingSection: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
            Text(NSLocalizedString("skimming.generating", comment: ""))
                .foregroundColor(.white.opacity(0.8))
            
            // AI 免责声明（底部）
            HStack {
                Image(systemName: "info.circle")
                    .font(.caption2)
                Text(NSLocalizedString("ai.disclaimer", comment: "AI disclaimer"))
                    .font(.caption2)
                Spacer()
            }
            .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
    
    private func chapterErrorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Button(NSLocalizedString("skimming.retry", comment: ""), action: onRequestSummary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.15))
                .cornerRadius(12)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func summarySections(_ summary: SkimmingChapterSummary) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            SkimmingTimeBadge(minutes: summary.estimatedMinutes)
            SkimmingGoalCard(goal: summary.readingGoal)
            SkimmingStructureSection(points: summary.structure)
            SkimmingKeySentencesSection(sentences: summary.keySentences)
            SkimmingKeywordsSection(keywords: summary.keywords)
            SkimmingQuestionsSection(questions: summary.inspectionQuestions)
            SkimmingNarrativeSection(text: summary.aiNarrative)
            Button(action: onStartFullReading) {
                HStack {
                    Image(systemName: "arrow.right.circle.fill")
                    Text(NSLocalizedString("skimming.start_chapter_reading", comment: ""))
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(.blue.opacity(0.8))
                .cornerRadius(16)
            }
            
            // AI 免责声明
            HStack {
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                Text(NSLocalizedString("ai.disclaimer", comment: "AI disclaimer"))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
            }
        }
    }
    
    private var placeholderView: some View {
        VStack(spacing: 8) {
            Text(NSLocalizedString("skimming.placeholder", comment: ""))
                .foregroundColor(.white.opacity(0.7))
            Button(NSLocalizedString("skimming.generate", comment: ""), action: onRequestSummary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.15))
                .cornerRadius(12)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SkimmingTimeBadge: View {
    let minutes: Int
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hourglass")
                .foregroundColor(.yellow)
            Text(String(format: NSLocalizedString("skimming.time_estimate", comment: ""), minutes))
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
        .foregroundColor(.white)
    }
}

private struct SkimmingGoalCard: View {
    let goal: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(NSLocalizedString("skimming.goal", comment: ""), systemImage: "target")
                .foregroundColor(.white)
                .font(.headline)
            Text(goal)
                .foregroundColor(.white)
                .lineSpacing(4)
        }
        .padding()
        .background(Color.blue.opacity(0.15))
        .cornerRadius(16)
    }
}

private struct SkimmingStructureSection: View {
    let points: [SkimmingStructurePoint]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(NSLocalizedString("skimming.structure", comment: ""), systemImage: "list.triangle")
                .foregroundColor(.white)
                .font(.headline)
            ForEach(points) { point in
                VStack(alignment: .leading, spacing: 4) {
                    Text(point.label)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    Text(point.insight)
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
            }
        }
    }
}

private struct SkimmingKeySentencesSection: View {
    let sentences: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(NSLocalizedString("skimming.key_sentences", comment: ""), systemImage: "quote.bubble")
                .foregroundColor(.white)
                .font(.headline)
            ForEach(Array(sentences.enumerated()), id: \.offset) { index, sentence in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .foregroundColor(.white.opacity(0.7))
                    Text(sentence)
                        .foregroundColor(.white)
                        .lineSpacing(4)
                }
            }
        }
    }
}

private struct SkimmingKeywordsSection: View {
    let keywords: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(NSLocalizedString("skimming.keywords", comment: ""), systemImage: "highlighter")
                .foregroundColor(.white)
                .font(.headline)
            FlexibleKeywordGrid(keywords: keywords)
        }
    }
}

private struct FlexibleKeywordGrid: View {
    let keywords: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(groupedKeywords(), id: \.self) { row in
                HStack {
                    ForEach(row, id: \.self) { word in
                        Text(word)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(20)
                            .foregroundColor(.white)
                    }
                    Spacer()
                }
            }
        }
    }
    
    private func groupedKeywords() -> [[String]] {
        guard !keywords.isEmpty else { return [] }
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentCount = 0
        for word in keywords {
            let length = word.count + 4
            if currentCount + length > 20 && !currentRow.isEmpty {
                rows.append(currentRow)
                currentRow = [word]
                currentCount = length
            } else {
                currentRow.append(word)
                currentCount += length
            }
        }
        if !currentRow.isEmpty {
            rows.append(currentRow)
        }
        return rows
    }
}

private struct SkimmingQuestionsSection: View {
    let questions: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(NSLocalizedString("skimming.questions", comment: ""), systemImage: "questionmark.circle")
                .foregroundColor(.white)
                .font(.headline)
            ForEach(questions, id: \.self) { question in
                Text("• \(question)")
                    .foregroundColor(.white)
            }
        }
    }
}

private struct SkimmingNarrativeSection: View {
    let text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(NSLocalizedString("skimming.narrative", comment: ""), systemImage: "sparkles")
                .foregroundColor(.white)
                .font(.headline)
            MarkdownText(text, lineSpacing: 6, textColor: .white)
        }
    }
}

private struct SkimmingTableOfContentsView: View {
    let chapters: [SkimmingChapterMetadata]
    @Binding var currentChapterIndex: Int
    let summaries: [Int: SkimmingChapterSummary]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(chapters.indices, id: \.self) { index in
                    Button(action: {
                        currentChapterIndex = index
                        dismiss()
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(chapters[index].title)
                                    .foregroundColor(.primary)
                                    .fontWeight(index == currentChapterIndex ? .bold : .regular)
                                    .lineLimit(2)
                                if let summary = summaries[index] {
                                    Text(summary.keywords.prefix(3).joined(separator: " • "))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if summaries[index] != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("目录", comment: ""))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("取消", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
    }
}
