//
//  ProfileSettingsView.swift
//  LanRead
//
//  Created by Codex on 2026/3/31.
//

import SwiftUI
import PhotosUI

struct ProfileSettingsView: View {
    @StateObject private var appSettings = AppSettings.shared
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var isLoadingAvatar = false
    @State private var avatarAlert: AvatarAlert?
    @FocusState private var isDisplayNameFocused: Bool

    private let maxDisplayNameLength = 24

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    PhotosPicker(
                        selection: $selectedAvatarItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        ProfileAvatarPreview(
                            avatarData: appSettings.profileAvatarData,
                            displayName: resolvedDisplayName,
                            size: 72,
                            showLoadingOverlay: isLoadingAvatar
                        )
                        .overlay(alignment: .bottom) {
                            Text(NSLocalizedString("settings.profile.avatar.edit", comment: ""))
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: Capsule())
                                .offset(y: 12)
                        }
                        .padding(.bottom, 12)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoadingAvatar)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(resolvedDisplayName)
                            .font(.headline)
                        Text(NSLocalizedString("settings.profile.preview_hint", comment: ""))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section(NSLocalizedString("settings.profile.display_name", comment: "")) {
                TextField(
                    NSLocalizedString("settings.profile.display_name.placeholder", comment: ""),
                    text: $appSettings.profileDisplayName
                )
                .focused($isDisplayNameFocused)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)

                HStack {
                    Text(NSLocalizedString("settings.profile.default_name_hint", comment: ""))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(appSettings.profileDisplayName.count)/\(maxDisplayNameLength)")
                        .font(.footnote.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }

            if appSettings.profileAvatarData != nil {
                Section(NSLocalizedString("settings.profile.avatar", comment: "")) {
                    Button(role: .destructive) {
                        appSettings.setProfileAvatar(from: nil)
                    } label: {
                        Label(
                            NSLocalizedString("settings.profile.avatar.remove", comment: ""),
                            systemImage: "trash"
                        )
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("settings.profile.title", comment: ""))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert(item: $avatarAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(NSLocalizedString("common.confirm", comment: "")))
            )
        }
        .onChange(of: selectedAvatarItem) { newValue in
            guard let newValue else { return }
            loadSelectedAvatar(newValue)
        }
        .onChange(of: appSettings.profileDisplayName) { newValue in
            if newValue.count > maxDisplayNameLength {
                appSettings.profileDisplayName = String(newValue.prefix(maxDisplayNameLength))
            }
        }
    }

    private var resolvedDisplayName: String {
        appSettings.resolvedProfileDisplayName(
            fallback: NSLocalizedString("settings.profile.default_display_name", comment: "")
        )
    }

    private func loadSelectedAvatar(_ item: PhotosPickerItem) {
        guard !isLoadingAvatar else { return }
        isLoadingAvatar = true

        Task {
            do {
                let data = try await item.loadTransferable(type: Data.self)
                await MainActor.run {
                    appSettings.updateProfileAvatar(withRawData: data)
                    isLoadingAvatar = false
                    selectedAvatarItem = nil
                }
            } catch {
                await MainActor.run {
                    isLoadingAvatar = false
                    selectedAvatarItem = nil
                    avatarAlert = AvatarAlert(
                        title: NSLocalizedString("settings.profile.avatar.load_failed.title", comment: ""),
                        message: NSLocalizedString("settings.profile.avatar.load_failed.message", comment: "")
                    )
                }
                DebugLogger.error("ProfileSettingsView: 头像加载失败", error: error)
            }
        }
    }
}

private struct AvatarAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct ProfileAvatarPreview: View {
    let avatarData: Data?
    let displayName: String
    let size: CGFloat
    let showLoadingOverlay: Bool

    var body: some View {
        Group {
            if let avatarData, let image = UIImage(data: avatarData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.44, green: 0.62, blue: 0.96),
                                    Color(red: 0.27, green: 0.45, blue: 0.85)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text(initialLetter)
                        .font(.system(size: size * 0.43, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.72), lineWidth: 1.2)
        )
        .overlay {
            if showLoadingOverlay {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.28))
                    ProgressView()
                        .tint(.white)
                }
            }
        }
        .shadow(color: Color.black.opacity(0.14), radius: 4, x: 0, y: 2)
    }

    private var initialLetter: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let letter = String(trimmed.prefix(1)).uppercased()
        return letter.isEmpty ? "U" : letter
    }
}
