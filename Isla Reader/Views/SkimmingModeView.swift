//
//  SkimmingModeView.swift
//  LanRead
//
//  Created by AI Assistant on 2025/1/22.
//

import SwiftUI
import CoreData

struct SkimmingModeView: View {
    let book: Book
    
    @StateObject private var appSettings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.scenePhase) private var scenePhase
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
    @State private var forwardChapterSwipeCount = 0
    @State private var interstitialPresentedCount = 0
    @State private var adNoticeMessage: String?
    @State private var adNoticeDismissTask: Task<Void, Never>?
    @State private var pendingInterstitialBeforeNextChapter = false
    @State private var thirdNoticeShownTriggerCounts: Set<Int> = []
    @State private var lastChapterLoadingNoticeAt: Date?
    @State private var loadingSwipeOffset: CGFloat = 0
    @State private var didShowLoadingNoticeInCurrentDrag = false
    @State private var didNavigateBackwardInCurrentDrag = false
    @State private var readingStartTime: Date?
    @State private var isActivelyReading = false
    @State private var readingHeartbeatTask: Task<Void, Never>?
    @State private var lastPublishedLiveActivityMinute: Int = -1
    @State private var lastReportedSkimmingChapterIndex: Int?
    
    private let service = SkimmingModeService.shared
    private let preloadAheadChapterCount = 3
    private let chapterLoadingNoticeCooldown: TimeInterval = 1.5
    private let readingHeartbeatIntervalNanoseconds: UInt64 = 15_000_000_000
    
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
                restoreAdProgressState()
                loadChapters()
                startReadingSession()
                startReadingHeartbeat()
                syncLiveActivityReadingProgressIfNeeded(reason: "skimming.onAppear")
                if appSettings.areAdsEnabled {
                    RewardedInterstitialAdManager.shared.loadAd()
                }
            }
            .onDisappear {
                stopReadingHeartbeat()
                endReadingSession()
                adNoticeDismissTask?.cancel()
            }
            .onChange(of: scenePhase) { newPhase in
                handleScenePhaseChange(newPhase)
            }
            .onChange(of: appSettings.areAdsEnabled) { enabled in
                if enabled {
                    updateInterstitialReadinessIfNeeded(for: currentChapterIndex)
                    return
                }
                pendingInterstitialBeforeNextChapter = false
                dismissAdvanceNotice()
            }
            .overlay(alignment: .top) {
                if let adNoticeMessage {
                    adNoticeBanner(adNoticeMessage, onClose: dismissAdvanceNotice)
                        .padding(.top, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .sheet(isPresented: $showingTOC) {
                SkimmingTableOfContentsView(
                    chapters: chapters,
                    currentChapterIndex: chapterSelectionBinding,
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
                    Label(NSLocalizedString("reader.toc.title", comment: ""), systemImage: "list.bullet")
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
        TabView(selection: chapterSelectionBinding) {
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
        .offset(x: loadingSwipeOffset)
        .background(
            SkimmingPagerSwipeLockConfigurator(isLocked: isCurrentChapterLoading)
        )
        .overlay {
            if isCurrentChapterLoading {
                Color.clear
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { value in
                                guard abs(value.translation.width) > abs(value.translation.height) else { return }

                                if value.translation.width > 56,
                                   !didNavigateBackwardInCurrentDrag {
                                    didNavigateBackwardInCurrentDrag = true
                                    loadingSwipeOffset = 0
                                    navigateToPreviousChapterFromLoadingDrag()
                                    return
                                }

                                let dampedOffset = max(-36, min(36, value.translation.width * 0.28))
                                loadingSwipeOffset = dampedOffset

                                if abs(value.translation.width) > 20,
                                   value.translation.width < 0,
                                   !didShowLoadingNoticeInCurrentDrag {
                                    didShowLoadingNoticeInCurrentDrag = true
                                    maybeShowChapterLoadingNotice()
                                }
                            }
                            .onEnded { _ in
                                didShowLoadingNoticeInCurrentDrag = false
                                didNavigateBackwardInCurrentDrag = false
                                withAnimation(.interpolatingSpring(stiffness: 360, damping: 28)) {
                                    loadingSwipeOffset = 0
                                }
                            }
                    )
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: currentChapterIndex) { newValue in
            guard chapters.indices.contains(newValue) else { return }
            service.storeLastVisitedChapterIndex(newValue, for: book)
            preloadSummaries(from: newValue)
            reportSkimmingChapterOpenMetric(for: newValue)
        }
        .onChange(of: isCurrentChapterLoading) { newValue in
            if !newValue {
                didShowLoadingNoticeInCurrentDrag = false
                didNavigateBackwardInCurrentDrag = false
                withAnimation(.easeOut(duration: 0.16)) {
                    loadingSwipeOffset = 0
                }
            }
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

    private var chapterSelectionBinding: Binding<Int> {
        Binding(
            get: { currentChapterIndex },
            set: { newValue in
                guard chapters.indices.contains(newValue) else { return }
                guard newValue != currentChapterIndex else { return }

                let previousChapterIndex = currentChapterIndex
                if newValue > previousChapterIndex {
                    guard !shouldBlockForwardNavigation(from: previousChapterIndex) else {
                        preloadSummaries(from: previousChapterIndex)
                        maybeShowChapterLoadingNotice()
                        return
                    }
                    incrementForwardChapterSwipeCountAndPrepareAdIfNeeded(for: previousChapterIndex)
                    handlePendingInterstitialBeforeChapterAdvance()
                }
                currentChapterIndex = newValue
            }
        )
    }
    
    private func openReader(at index: Int) {
        guard chapters.indices.contains(index) else { return }
        let chapter = chapters[index]
        DebugLogger.info(
            "SkimmingModeView: 跳转全文阅读，skimmingIndex=\(index), readerChapterIndex=\(chapter.readerChapterIndex), fragment=\(chapter.sourceFragment ?? "nil")"
        )
        let location = BookmarkLocation(
            chapterIndex: chapter.readerChapterIndex,
            pageIndex: 0,
            chapterTitle: chapter.title,
            tocFragment: chapter.sourceFragment
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
                    self.chapters = metadata
                    self.isLoadingChapters = false
                    let restoredIndex = self.initialChapterIndex(for: metadata.count)
                    self.currentChapterIndex = restoredIndex
                    // 从缓存中恢复已生成的摘要
                    self.restoreCachedSummaries()
                    self.preloadSummaries(from: restoredIndex)
                    self.reportSkimmingChapterOpenMetric(for: restoredIndex)
                }
            } catch {
                await MainActor.run {
                    self.isLoadingChapters = false
                    self.loadError = error.localizedDescription
                }
            }
        }
    }

    private func reportSkimmingChapterOpenMetric(for index: Int) {
        guard chapters.indices.contains(index) else { return }
        guard lastReportedSkimmingChapterIndex != index else { return }
        UsageMetricsReporter.shared.record(
            interface: UsageMetricsInterface.readerSkimmingChapterOpen,
            statusCode: 200,
            latencyMs: 0,
            requestBytes: 0,
            retryCount: 0,
            source: .reader
        )
        lastReportedSkimmingChapterIndex = index
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
                    incrementSkimmingUsageAndPrepareAdIfNeeded(for: index)
                }
            } catch {
                await MainActor.run {
                    self.loadingChapterIndices.remove(index)
                    self.chapterErrors[index] = error.localizedDescription
                }
            }
        }
    }

    @MainActor
    private func preloadSummaries(from index: Int) {
        guard chapters.indices.contains(index) else { return }
        let upperBound = min(chapters.count - 1, index + preloadAheadChapterCount)
        for chapterIndex in index...upperBound {
            requestSummary(for: chapterIndex)
        }
    }

    private func shouldBlockForwardNavigation(from index: Int) -> Bool {
        guard chapters.indices.contains(index) else { return false }
        guard chapterSummaries[index] == nil else { return false }
        return loadingChapterIndices.contains(index)
    }

    private func shouldPromptWaitForCurrentChapter(at index: Int) -> Bool {
        guard chapters.indices.contains(index) else { return false }
        guard chapterSummaries[index] == nil else { return false }
        return loadingChapterIndices.contains(index)
    }

    private var isCurrentChapterLoading: Bool {
        shouldPromptWaitForCurrentChapter(at: currentChapterIndex)
    }

    @MainActor
    private func maybeShowChapterLoadingNotice() {
        let now = Date()
        if let lastShown = lastChapterLoadingNoticeAt,
           now.timeIntervalSince(lastShown) < chapterLoadingNoticeCooldown {
            return
        }
        lastChapterLoadingNoticeAt = now
        showAdvanceNotice(NSLocalizedString("skimming.wait_for_chapter_loading", comment: ""))
    }

    @MainActor
    private func navigateToPreviousChapterFromLoadingDrag() {
        guard currentChapterIndex > 0 else { return }
        withAnimation(.easeOut(duration: 0.22)) {
            currentChapterIndex -= 1
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
    private func incrementSkimmingUsageAndPrepareAdIfNeeded(for chapterIndex: Int) {
        skimmingAIRequestCount += 1
        DebugLogger.info("SkimmingModeView: 略读AI调用计数 = \(skimmingAIRequestCount)")
        persistAdProgressState()
        updateInterstitialReadinessIfNeeded(for: chapterIndex)
    }

    @MainActor
    private func incrementForwardChapterSwipeCountAndPrepareAdIfNeeded(for chapterIndex: Int) {
        forwardChapterSwipeCount += 1
        DebugLogger.info("SkimmingModeView: 前进滑动章节计数 = \(forwardChapterSwipeCount)")
        persistAdProgressState()
        updateInterstitialReadinessIfNeeded(for: chapterIndex)
    }

    @MainActor
    private func updateInterstitialReadinessIfNeeded(for chapterIndex: Int) {
        guard appSettings.areAdsEnabled else {
            pendingInterstitialBeforeNextChapter = false
            return
        }
        let completedTriggerCount = min(skimmingAIRequestCount / 3, forwardChapterSwipeCount / 3)
        guard completedTriggerCount > interstitialPresentedCount else { return }
        pendingInterstitialBeforeNextChapter = true
        RewardedInterstitialAdManager.shared.loadAd()
        DebugLogger.info(
            "SkimmingModeView: 满足插屏阈值，准备在下一次进入新章节前展示。AI计数=\(skimmingAIRequestCount), 滑动计数=\(forwardChapterSwipeCount), 已展示=\(interstitialPresentedCount)"
        )
        maybeShowThirdAdvanceNotice(forTriggerCount: completedTriggerCount)
    }

    @MainActor
    private func handlePendingInterstitialBeforeChapterAdvance() {
        guard appSettings.areAdsEnabled else {
            pendingInterstitialBeforeNextChapter = false
            return
        }
        guard pendingInterstitialBeforeNextChapter else { return }
        Task { @MainActor in
            await Task.yield()

            let result = RewardedInterstitialAdManager.shared.presentFromTopControllerIfAvailable()
            switch result {
            case .presented:
                pendingInterstitialBeforeNextChapter = false
                interstitialPresentedCount += 1
                persistAdProgressState()
                DebugLogger.info("SkimmingModeView: 已在章节切换前展示奖励插屏广告")
                updateInterstitialReadinessIfNeeded(for: currentChapterIndex)
            case .skippedNotReady:
                DebugLogger.info("SkimmingModeView: 广告未就绪，已跳过提示弹窗")
            case .skippedNoTopViewController:
                DebugLogger.warning("SkimmingModeView: 章节切换前未找到可展示广告的控制器，已跳过")
            }
        }
    }

    @MainActor
    private func maybeShowThirdAdvanceNotice(forTriggerCount triggerCount: Int) {
        guard !thirdNoticeShownTriggerCounts.contains(triggerCount) else { return }
        thirdNoticeShownTriggerCounts.insert(triggerCount)
        persistAdProgressState()

        let availability = RewardedInterstitialAdManager.shared.availabilityStatus()
        switch availability {
        case .ready:
            showAdvanceNoticeIfEnabled("skimming.ad_notice.third_ready")
        case .loading, .notReady:
            showAdvanceNoticeIfEnabled("skimming.ad_notice.third_maybe")
        }
    }

    @MainActor
    private func showAdvanceNoticeIfEnabled(_ key: String) {
        guard appSettings.shouldShowAIAdvanceAdNotice else { return }
        showAdvanceNotice(NSLocalizedString(key, comment: ""))
    }

    @MainActor
    private func showAdvanceNotice(_ message: String) {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }
        if adNoticeMessage == trimmedMessage, adNoticeDismissTask != nil {
            return
        }

        adNoticeDismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            adNoticeMessage = trimmedMessage
        }

        adNoticeDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_400_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                adNoticeMessage = nil
            }
            adNoticeDismissTask = nil
        }
    }

    @MainActor
    private func dismissAdvanceNotice() {
        adNoticeDismissTask?.cancel()
        adNoticeDismissTask = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            adNoticeMessage = nil
        }
    }

    private func adNoticeBanner(_ message: String, onClose: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundColor(Color(uiColor: .label))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .layoutPriority(1)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundColor(Color(uiColor: .secondaryLabel))
                    .frame(width: 22, height: 22)
                    .background(Color(uiColor: .tertiarySystemFill))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(NSLocalizedString("common.close", comment: "")))
        }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground).opacity(0.94))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .padding(.horizontal, 16)
    }

    @MainActor
    private func restoreAdProgressState() {
        let adProgress = service.adProgress(for: book)
        skimmingAIRequestCount = adProgress.skimmingAIRequestCount
        forwardChapterSwipeCount = adProgress.forwardChapterSwipeCount
        interstitialPresentedCount = adProgress.interstitialPresentedCount
        thirdNoticeShownTriggerCounts = Set(adProgress.thirdNoticeShownTriggerCounts)

        DebugLogger.info(
            "SkimmingModeView: 已恢复广告计数。AI计数=\(skimmingAIRequestCount), 滑动计数=\(forwardChapterSwipeCount), 已展示=\(interstitialPresentedCount)"
        )
        updateInterstitialReadinessIfNeeded(for: currentChapterIndex)
    }

    @MainActor
    private func persistAdProgressState() {
        let adProgress = SkimmingAdProgress(
            skimmingAIRequestCount: skimmingAIRequestCount,
            forwardChapterSwipeCount: forwardChapterSwipeCount,
            interstitialPresentedCount: interstitialPresentedCount,
            thirdNoticeShownTriggerCounts: Array(thirdNoticeShownTriggerCounts)
        )
        service.storeAdProgress(adProgress, for: book)
    }

    // MARK: - Reading Time Tracking

    private func startReadingSession() {
        readingStartTime = Date()
        isActivelyReading = true
        syncLiveActivityReadingProgressIfNeeded(reason: "skimming.startReadingSession")

        if let libraryItem = book.libraryItem,
           (libraryItem.status == .wantToRead || libraryItem.status == .paused) {
            libraryItem.status = .reading
            libraryItem.lastAccessedAt = Date()

            do {
                try viewContext.save()
                DebugLogger.info("SkimmingModeView: Updated status to 'reading'")
            } catch {
                DebugLogger.error("SkimmingModeView: Failed to update reading status: \(error)")
            }
        }
    }

    private func endReadingSession() {
        updateReadingTime()
        readingStartTime = nil
        isActivelyReading = false
        syncLiveActivityReadingProgressIfNeeded(reason: "skimming.endReadingSession")
    }

    private func pauseReadingSession() {
        updateReadingTime()
        readingStartTime = nil
        isActivelyReading = false
        syncLiveActivityReadingProgressIfNeeded(reason: "skimming.pauseReadingSession")
    }

    private func resumeReadingSession() {
        readingStartTime = Date()
        isActivelyReading = true
        syncLiveActivityReadingProgressIfNeeded(reason: "skimming.resumeReadingSession")
    }

    private func updateReadingTime(resetStartTime: Bool = false) {
        guard let startTime = readingStartTime, isActivelyReading else { return }

        let now = Date()
        let timeElapsed = now.timeIntervalSince(startTime)
        guard timeElapsed > 1 else { return }

        let elapsedSeconds = Int(timeElapsed.rounded(.down))
        guard elapsedSeconds > 0 else { return }

        let progress = readingProgress(for: now)
        progress.migrateLegacyReadingTimeBucketsIfNeeded()
        progress.totalReadingTime += Int64(elapsedSeconds)
        progress.skimmingReadingTime += Int64(elapsedSeconds)
        progress.lastReadAt = now
        progress.updatedAt = now

        if let libraryItem = book.libraryItem {
            libraryItem.lastAccessedAt = now
        }

        do {
            try viewContext.save()
            ReadingDailyStatsStore.shared.addReadingSeconds(elapsedSeconds)
            syncLiveActivityReadingProgressIfNeeded(reason: "skimming.updateReadingTime")
        } catch {
            DebugLogger.error("SkimmingModeView: Failed to save reading time: \(error)")
        }

        if resetStartTime {
            readingStartTime = now
        }
    }

    private func readingProgress(for now: Date) -> ReadingProgress {
        if let existingProgress = book.readingProgress {
            return existingProgress
        }

        let progress = ReadingProgress(context: viewContext)
        progress.id = UUID()
        progress.currentPage = 0
        progress.currentChapter =
            chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : nil
        progress.currentPosition = nil
        progress.progressPercentage = 0
        progress.lastReadAt = now
        progress.totalReadingTime = 0
        progress.detailedReadingTime = 0
        progress.skimmingReadingTime = 0
        progress.createdAt = now
        progress.updatedAt = now
        progress.book = book
        book.readingProgress = progress
        return progress
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            if !isActivelyReading {
                resumeReadingSession()
            }
        case .inactive, .background:
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
            "[LiveActivityFlow] Syncing Live Activity reading progress from SkimmingModeView. " +
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
}

private struct SkimmingPagerSwipeLockConfigurator: UIViewRepresentable {
    let isLocked: Bool

    func makeUIView(context: Context) -> UIView {
        UIView(frame: .zero)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            guard let pagingScrollView = findPagingScrollView(from: uiView) else { return }
            let shouldEnableScroll = !isLocked
            if pagingScrollView.isScrollEnabled != shouldEnableScroll {
                pagingScrollView.isScrollEnabled = shouldEnableScroll
            }
        }
    }

    private func findPagingScrollView(from anchorView: UIView) -> UIScrollView? {
        var current: UIView? = anchorView
        while let view = current {
            if let found = searchPagingScrollView(in: view) {
                return found
            }
            current = view.superview
        }
        return nil
    }

    private func searchPagingScrollView(in root: UIView) -> UIScrollView? {
        if let scrollView = root as? UIScrollView, scrollView.isPagingEnabled {
            return scrollView
        }

        for subview in root.subviews {
            if let found = searchPagingScrollView(in: subview) {
                return found
            }
        }
        return nil
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
            .navigationTitle(NSLocalizedString("reader.toc.title", comment: ""))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("common.cancel", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
    }
}
