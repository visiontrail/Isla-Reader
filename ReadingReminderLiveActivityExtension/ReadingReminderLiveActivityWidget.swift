//
//  ReadingReminderLiveActivityWidget.swift
//  ReadingReminderLiveActivityExtension
//
//  Created by Assistant on 2026/2/10.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct ReadingReminderLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReadingReminderAttributes.self) { context in
            ReadingReminderLockScreenView(context: context)
                .widgetURL(destinationURL(from: context.state.deepLink))
                .activityBackgroundTint(.clear)
                .activitySystemActionForegroundColor(.blue)
        } dynamicIsland: { _ in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { EmptyView() }
                DynamicIslandExpandedRegion(.trailing) { EmptyView() }
                DynamicIslandExpandedRegion(.center) { EmptyView() }
                DynamicIslandExpandedRegion(.bottom) { EmptyView() }
            } compactLeading: {
                EmptyView()
            } compactTrailing: {
                EmptyView()
            } minimal: {
                EmptyView()
            }
        }
    }

    private func destinationURL(from deepLink: String) -> URL {
        URL(string: deepLink) ?? URL(string: "isla-reader://read/last")!
    }
}

private struct ReadingReminderLockScreenView: View {
    let context: ActivityViewContext<ReadingReminderAttributes>

    private var goalText: String {
        "Today: \(max(0, context.state.minutesReadToday)) / \(max(1, context.state.goalMinutes)) min"
    }

    private var continueURL: URL {
        URL(string: context.state.deepLink) ?? URL(string: "isla-reader://read/last")!
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("📖 Start Reading")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.78))
                .lineLimit(1)

            Text(goalText)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.72))
                .lineLimit(1)

            Link(destination: continueURL) {
                Text("Continue Reading")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.29, green: 0.53, blue: 0.95),
                                        Color(red: 0.24, green: 0.45, blue: 0.90)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.97, green: 0.96, blue: 0.93),
                            Color(red: 0.95, green: 0.94, blue: 0.91)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(PaperGrainOverlay().clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.05), lineWidth: 0.5)
                )
        )
    }
}

private struct PaperGrainOverlay: View {
    var body: some View {
        Canvas { context, size in
            let count = max(180, Int((size.width * size.height) / 220))

            for index in 0..<count {
                let x = seed(index, salt: 13.0) * size.width
                let y = seed(index, salt: 71.0) * size.height
                let width = 0.6 + seed(index, salt: 151.0) * 1.2
                let height = 0.6 + seed(index, salt: 241.0) * 1.2
                let alpha = 0.015 + seed(index, salt: 331.0) * 0.02

                let rect = CGRect(x: x, y: y, width: width, height: height)
                context.fill(Path(rect), with: .color(Color.black.opacity(alpha)))
            }
        }
        .blendMode(.multiply)
        .allowsHitTesting(false)
    }

    private func seed(_ index: Int, salt: Double) -> CGFloat {
        let value = sin(Double(index) * 12.9898 + salt) * 43758.5453
        return CGFloat(value - floor(value))
    }
}
