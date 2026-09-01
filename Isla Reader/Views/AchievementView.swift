//
//  AchievementView.swift
//  LanRead
//

import SwiftUI

struct AchievementSummarySection: View {
    let metrics: AchievementMetrics
    @ObservedObject var store: AchievementStore

    private var unlockedCount: Int {
        store.unlockedCount()
    }

    var body: some View {
        NavigationLink {
            AchievementGalleryView(metrics: metrics, store: store)
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("achievement.section.title", comment: ""))
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)

                        Text(String(
                            format: NSLocalizedString("achievement.unlocked_count.format", comment: ""),
                            unlockedCount,
                            AchievementCatalog.all.count
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Text(NSLocalizedString("achievement.view_all", comment: ""))
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
                }

                HStack(spacing: 12) {
                    ForEach(AchievementCatalog.all.prefix(4)) { achievement in
                        AchievementBadgeArt(
                            achievement: achievement,
                            isUnlocked: store.isUnlocked(achievement),
                            size: 58,
                            showsLock: true
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [Color.blue.opacity(0.10), Color.purple.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.blue.opacity(0.16), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("achievement.view_all")
        .accessibilityLabel(String(
            format: NSLocalizedString("achievement.summary.accessibility", comment: ""),
            unlockedCount,
            AchievementCatalog.all.count
        ))
    }
}

struct AchievementGalleryView: View {
    let metrics: AchievementMetrics
    @ObservedObject var store: AchievementStore

    @State private var selectedAchievement: AchievementDefinition?

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                galleryHeader

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(AchievementCatalog.all) { achievement in
                        AchievementCell(
                            achievement: achievement,
                            metrics: metrics,
                            isUnlocked: store.isUnlocked(achievement)
                        ) {
                            selectedAchievement = achievement
                        }
                    }
                }
            }
            .padding()
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(NSLocalizedString("achievement.gallery.title", comment: ""))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $selectedAchievement) { achievement in
            AchievementDetailView(
                achievement: achievement,
                metrics: metrics,
                store: store
            )
        }
        .accessibilityIdentifier("achievement.gallery")
    }

    private var galleryHeader: some View {
        VStack(spacing: 10) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.yellow)
                .padding(13)
                .background(Color.orange.opacity(0.14), in: Circle())

            Text(String(
                format: NSLocalizedString("achievement.unlocked_count.format", comment: ""),
                store.unlockedCount(),
                AchievementCatalog.all.count
            ))
            .font(.title2.bold())

            Text(NSLocalizedString("achievement.gallery.subtitle", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

private struct AchievementCell: View {
    let achievement: AchievementDefinition
    let metrics: AchievementMetrics
    let isUnlocked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                AchievementBadgeArt(
                    achievement: achievement,
                    isUnlocked: isUnlocked,
                    size: 112,
                    showsLock: true
                )

                Text(NSLocalizedString(achievement.titleKey, comment: ""))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if isUnlocked {
                    Label(
                        NSLocalizedString("achievement.earned", comment: ""),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                } else {
                    achievementProgress
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("achievement.badge.\(achievement.id)")
        .accessibilityLabel(accessibilityLabel)
    }

    private var achievementProgress: some View {
        VStack(spacing: 6) {
            ProgressView(value: achievement.progressFraction(in: metrics))
                .tint(.blue)

            Text(String(
                format: NSLocalizedString("achievement.progress.format", comment: ""),
                achievement.progress(in: metrics),
                achievement.goal.target
            ))
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var accessibilityLabel: String {
        let title = NSLocalizedString(achievement.titleKey, comment: "")
        if isUnlocked {
            return "\(title), \(NSLocalizedString("achievement.earned", comment: ""))"
        }
        return "\(title), " + String(
            format: NSLocalizedString("achievement.progress.format", comment: ""),
            achievement.progress(in: metrics),
            achievement.goal.target
        )
    }
}

struct AchievementBadgeArt: View {
    let achievement: AchievementDefinition
    let isUnlocked: Bool
    let size: CGFloat
    let showsLock: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: size, height: size)

            Image(achievement.assetName)
                .resizable()
                .scaledToFit()
                .frame(width: size * 1.18, height: size * 1.18)
                .saturation(isUnlocked ? 1 : 0)
                .opacity(isUnlocked ? 1 : 0.42)
                .frame(width: size, height: size)
                .clipShape(Circle())

            if showsLock && !isUnlocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: size * 0.14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(size * 0.075)
                    .background(Color(.systemGray), in: Circle())
                    .overlay {
                        Circle().stroke(Color(.systemBackground), lineWidth: 2)
                    }
            }
        }
        .frame(width: size, height: size)
    }
}

private struct AchievementDetailView: View {
    let achievement: AchievementDefinition
    let metrics: AchievementMetrics
    @ObservedObject var store: AchievementStore

    @Environment(\.dismiss) private var dismiss

    private var isUnlocked: Bool {
        store.isUnlocked(achievement)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                AchievementBadgeArt(
                    achievement: achievement,
                    isUnlocked: isUnlocked,
                    size: 190,
                    showsLock: true
                )
                .padding(.top, 16)

                VStack(spacing: 8) {
                    Text(NSLocalizedString(achievement.titleKey, comment: ""))
                        .font(.title2.bold())

                    Text(NSLocalizedString(achievement.descriptionKey, comment: ""))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let unlockedAt = store.unlockedAt(for: achievement) {
                    Label {
                        Text(String(
                            format: NSLocalizedString("achievement.earned_on.format", comment: ""),
                            unlockedAt.formatted(date: .abbreviated, time: .omitted)
                        ))
                    } icon: {
                        Image(systemName: "checkmark.seal.fill")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                } else {
                    VStack(spacing: 8) {
                        ProgressView(value: achievement.progressFraction(in: metrics))
                            .tint(.blue)

                        Text(String(
                            format: NSLocalizedString("achievement.progress.format", comment: ""),
                            achievement.progress(in: metrics),
                            achievement.goal.target
                        ))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 28)
                }

                Spacer()
            }
            .padding()
            .navigationTitle(NSLocalizedString("achievement.detail.title", comment: ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("common.done", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct AchievementUnlockCelebrationView: View {
    let event: AchievementUnlockEvent
    let onContinue: () -> Void

    private var primaryAchievement: AchievementDefinition? {
        event.achievements.first
    }

    var body: some View {
        VStack(spacing: 18) {
            if let achievement = primaryAchievement {
                ZStack {
                    ForEach(0..<8, id: \.self) { index in
                        Image(systemName: index.isMultiple(of: 2) ? "sparkle" : "star.fill")
                            .font(.system(size: index.isMultiple(of: 2) ? 13 : 9, weight: .bold))
                            .foregroundStyle(index.isMultiple(of: 3) ? .orange : .yellow)
                            .offset(
                                x: CGFloat(cos(Double(index) * .pi / 4)) * 112,
                                y: CGFloat(sin(Double(index) * .pi / 4)) * 82
                            )
                    }

                    AchievementBadgeArt(
                        achievement: achievement,
                        isUnlocked: true,
                        size: 178,
                        showsLock: false
                    )
                }

                Text(NSLocalizedString("achievement.celebration.title", comment: ""))
                    .font(.title2.bold())
                    .accessibilityIdentifier("achievement.celebration")

                Text(NSLocalizedString(achievement.titleKey, comment: ""))
                    .font(.headline)
                    .foregroundStyle(.blue)

                Text(NSLocalizedString(achievement.descriptionKey, comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if event.achievements.count > 1 {
                    Text(String(
                        format: NSLocalizedString("achievement.celebration.more.format", comment: ""),
                        event.achievements.count - 1
                    ))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }

            Button {
                onContinue()
            } label: {
                Text(NSLocalizedString("achievement.celebration.continue", comment: ""))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("achievement.celebration.continue")
        }
        .padding(24)
    }
}

private struct AchievementCelebrationHostModifier: ViewModifier {
    @ObservedObject var store: AchievementStore
    let priority: Int

    @State private var presenterID = UUID()

    func body(content: Content) -> some View {
        content
            .overlay {
                if let event = store.currentUnlockEvent,
                   store.activePresenterID == presenterID {
                    ZStack {
                        Color.black.opacity(0.38)
                            .ignoresSafeArea()

                        AchievementUnlockCelebrationView(
                            event: event,
                            onContinue: {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    store.dismissCurrentUnlockEvent()
                                }
                            }
                        )
                        .frame(maxWidth: 380)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .shadow(color: .black.opacity(0.24), radius: 28, y: 12)
                        .padding(24)
                    }
                    .zIndex(1_000)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    .accessibilityAddTraits(.isModal)
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: store.currentUnlockEvent?.id)
            .onAppear {
                store.registerPresenter(id: presenterID, priority: priority)
            }
            .onDisappear {
                store.unregisterPresenter(id: presenterID)
            }
    }
}

extension View {
    func achievementCelebrationHost(
        store: AchievementStore = .shared,
        priority: Int = 0
    ) -> some View {
        modifier(AchievementCelebrationHostModifier(store: store, priority: priority))
    }
}
