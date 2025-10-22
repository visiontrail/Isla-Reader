//
//  ProgressView.swift
//  Isla Reader
//
//  Created by 郭亮 on 2025/9/10.
//

import SwiftUI
import CoreData

struct ReadingProgressView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var appSettings = AppSettings.shared
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ReadingProgress.lastReadAt, ascending: false)],
        animation: .default)
    private var readingProgresses: FetchedResults<ReadingProgress>
    
    @State private var selectedTimeRange: TimeRange = .week
    
    enum TimeRange: String, CaseIterable {
        case week = "week"
        case month = "month"
        case year = "year"
        
        var displayNameKey: LocalizedStringKey {
            switch self {
            case .week:
                return "本周"
            case .month:
                return "本月"
            case .year:
                return "今年"
            }
        }
    }
    
    private var recentlyReadBooks: [ReadingProgress] {
        let calendar = Calendar.current
        let now = Date()
        
        return readingProgresses.filter { progress in
            switch selectedTimeRange {
            case .week:
                return calendar.isDate(progress.lastReadAt, equalTo: now, toGranularity: .weekOfYear)
            case .month:
                return calendar.isDate(progress.lastReadAt, equalTo: now, toGranularity: .month)
            case .year:
                return calendar.isDate(progress.lastReadAt, equalTo: now, toGranularity: .year)
            }
        }
    }
    
    private var totalReadingTime: Int64 {
        recentlyReadBooks.reduce(0) { $0 + $1.totalReadingTime }
    }
    
    private var averageProgress: Double {
        guard !recentlyReadBooks.isEmpty else { return 0 }
        let total = recentlyReadBooks.reduce(0.0) { $0 + $1.progressPercentage }
        return total / Double(recentlyReadBooks.count)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Time Range Picker
                    Picker(NSLocalizedString("时间范围", comment: ""), selection: $selectedTimeRange) {
                        ForEach(TimeRange.allCases, id: \.rawValue) { range in
                            Text(range.displayNameKey).tag(range)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    
                    // Statistics Cards
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        StatCard(
                            title: "阅读时长",
                            value: formatReadingTime(totalReadingTime),
                            icon: "clock",
                            color: .blue
                        )
                        
                        StatCard(
                            title: "平均进度",
                            value: String(format: "%.1f%%", averageProgress * 100),
                            icon: "chart.line.uptrend.xyaxis",
                            color: .green
                        )
                        
                        StatCard(
                            title: "阅读书籍",
                            value: "\(recentlyReadBooks.count)",
                            icon: "books.vertical",
                            color: .orange
                        )
                        
                        StatCard(
                            title: "目标达成",
                            value: goalAchievementText,
                            icon: "target",
                            color: .purple
                        )
                    }
                    .padding(.horizontal)
                    
                    // Reading Goal Section
                    ReadingGoalCard(
                        dailyGoal: appSettings.dailyReadingGoal,
                        currentProgress: Int(totalReadingTime / 60), // Convert to minutes
                        timeRange: selectedTimeRange
                    )
                    .padding(.horizontal)
                    
                    // Recent Reading Activity
                    if !recentlyReadBooks.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text(NSLocalizedString("最近阅读", comment: ""))
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            .padding(.horizontal)
                            
                            ForEach(recentlyReadBooks.prefix(5)) { progress in
                                RecentReadingCard(progress: progress)
                                    .padding(.horizontal)
                            }
                        }
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding(.vertical)
            }
            .navigationTitle(NSLocalizedString("阅读统计", comment: ""))
            .navigationBarTitleDisplayMode(.large)
        }
    }
    
    private var goalAchievementText: String {
        let dailyMinutes = Int(totalReadingTime / 60)
        let daysInRange = daysInCurrentRange()
        let targetMinutes = appSettings.dailyReadingGoal * daysInRange
        
        if targetMinutes > 0 {
            let percentage = min(100, (dailyMinutes * 100) / targetMinutes)
            return "\(percentage)%"
        }
        return "0%"
    }
    
    private func daysInCurrentRange() -> Int {
        switch selectedTimeRange {
        case .week:
            return 7
        case .month:
            return Calendar.current.range(of: .day, in: .month, for: Date())?.count ?? 30
        case .year:
            return Calendar.current.range(of: .day, in: .year, for: Date())?.count ?? 365
        }
    }
    
    private func formatReadingTime(_ seconds: Int64) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

struct StatCard: View {
    let title: LocalizedStringKey
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct ReadingGoalCard: View {
    let dailyGoal: Int
    let currentProgress: Int
    let timeRange: ReadingProgressView.TimeRange
    
    private var progressPercentage: Double {
        guard dailyGoal > 0 else { return 0 }
        return min(1.0, Double(currentProgress) / Double(dailyGoal))
    }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("阅读目标", comment: ""))
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(String(format: NSLocalizedString("daily_goal_minutes_format", comment: ""), dailyGoal))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(currentProgress)/\(dailyGoal)")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text(NSLocalizedString("分钟", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Progress Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(
                            gradient: Gradient(colors: [.blue, .purple]),
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: geometry.size.width * progressPercentage, height: 8)
                        .animation(.easeInOut(duration: 0.5), value: progressPercentage)
                }
            }
            .frame(height: 8)
            
            HStack {
                Text(String(format: NSLocalizedString("progress_completed_format", comment: ""), progressPercentage * 100))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if progressPercentage >= 1.0 {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(NSLocalizedString("目标达成!", comment: ""))
                            .foregroundColor(.green)
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct RecentReadingCard: View {
    let progress: ReadingProgress
    
    var body: some View {
        HStack(spacing: 12) {
            // Book Cover Placeholder
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(
                    gradient: Gradient(colors: [.blue.opacity(0.6), .purple.opacity(0.8)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 50, height: 70)
                .overlay(
                    Image(systemName: "book.closed")
                        .font(.title3)
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(progress.book.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                
                Text(progress.book.displayAuthor)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                HStack {
                    Text(progress.formattedProgress)
                        .font(.caption)
                        .foregroundColor(.blue)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text(formatLastRead(progress.lastReadAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func formatLastRead(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    ReadingProgressView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}