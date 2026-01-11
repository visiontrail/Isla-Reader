//
//  DeviceAdaptation.swift
//  LanRead
//
//  Created by 郭亮 on 2025/9/10.
//

import SwiftUI
import UIKit

// MARK: - Device Type Detection
extension UIDevice {
    static var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    
    static var isIPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
    
    static var isLandscape: Bool {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return false
        }
        return windowScene.interfaceOrientation.isLandscape
    }
}

// MARK: - Responsive Layout Helpers
struct ResponsiveLayout {
    static func columns(for horizontalSizeClass: UserInterfaceSizeClass?) -> Int {
        switch horizontalSizeClass {
        case .regular:
            return UIDevice.isIPad ? 4 : 3
        case .compact, .none:
            return 2
        @unknown default:
            return 2
        }
    }
    
    static func cardWidth(for horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        switch horizontalSizeClass {
        case .regular:
            return UIDevice.isIPad ? 160 : 140
        case .compact, .none:
            return 140
        @unknown default:
            return 140
        }
    }
    
    static func padding(for horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        switch horizontalSizeClass {
        case .regular:
            return UIDevice.isIPad ? 24 : 20
        case .compact, .none:
            return 16
        @unknown default:
            return 16
        }
    }
    
    static func spacing(for horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        switch horizontalSizeClass {
        case .regular:
            return UIDevice.isIPad ? 20 : 16
        case .compact, .none:
            return 12
        @unknown default:
            return 12
        }
    }
}

// MARK: - Adaptive Font Sizes
extension Font {
    static func adaptiveTitle(for horizontalSizeClass: UserInterfaceSizeClass?) -> Font {
        switch horizontalSizeClass {
        case .regular:
            return UIDevice.isIPad ? .largeTitle : .title
        case .compact, .none:
            return .title2
        @unknown default:
            return .title2
        }
    }
    
    static func adaptiveHeadline(for horizontalSizeClass: UserInterfaceSizeClass?) -> Font {
        switch horizontalSizeClass {
        case .regular:
            return UIDevice.isIPad ? .title2 : .headline
        case .compact, .none:
            return .headline
        @unknown default:
            return .headline
        }
    }
    
    static func adaptiveBody(for horizontalSizeClass: UserInterfaceSizeClass?) -> Font {
        switch horizontalSizeClass {
        case .regular:
            return UIDevice.isIPad ? .body : .body
        case .compact, .none:
            return .body
        @unknown default:
            return .body
        }
    }
}

// MARK: - Adaptive Navigation
struct AdaptiveNavigationView<Content: View>: View {
    let content: Content
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        if horizontalSizeClass == .regular && UIDevice.isIPad {
            NavigationSplitView {
                // Sidebar content would go here
                EmptyView()
            } detail: {
                content
            }
        } else {
            NavigationView {
                content
            }
            .navigationViewStyle(StackNavigationViewStyle())
        }
    }
}

// MARK: - Adaptive Grid
struct AdaptiveGrid<Content: View>: View {
    let content: Content
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private var columns: [GridItem] {
        let count = ResponsiveLayout.columns(for: horizontalSizeClass)
        let spacing = ResponsiveLayout.spacing(for: horizontalSizeClass)
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: ResponsiveLayout.spacing(for: horizontalSizeClass)) {
            content
        }
        .padding(.horizontal, ResponsiveLayout.padding(for: horizontalSizeClass))
    }
}

// MARK: - Adaptive Sheet Presentation
extension View {
    func adaptiveSheet<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        self.modifier(AdaptiveSheetModifier(isPresented: isPresented, content: content))
    }
}

struct AdaptiveSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let content: () -> SheetContent
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular && UIDevice.isIPad {
            content
                .sheet(isPresented: $isPresented) {
                    self.content()
                        .frame(minWidth: 500, minHeight: 600)
                }
        } else {
            content
                .sheet(isPresented: $isPresented, content: self.content)
        }
    }
}

// MARK: - Safe Area Helpers
extension View {
    func adaptivePadding() -> some View {
        self.modifier(AdaptivePaddingModifier())
    }
}

struct AdaptivePaddingModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, ResponsiveLayout.padding(for: horizontalSizeClass))
    }
}

// MARK: - Orientation Change Handler
class OrientationManager: ObservableObject {
    @Published var orientation: UIDeviceOrientation = UIDevice.current.orientation
    
    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(orientationChanged),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func orientationChanged() {
        DispatchQueue.main.async {
            self.orientation = UIDevice.current.orientation
        }
    }
}

// MARK: - Dynamic Type Support
extension View {
    func adaptiveDynamicTypeSize() -> some View {
        self.modifier(AdaptiveDynamicTypeSizeModifier())
    }
}

struct AdaptiveDynamicTypeSizeModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    func body(content: Content) -> some View {
        content
            .dynamicTypeSize(dynamicTypeSize > .accessibility1 ? .accessibility1 : dynamicTypeSize)
    }
}

// MARK: - Keyboard Avoidance
extension View {
    func keyboardAware() -> some View {
        self.modifier(KeyboardAwareModifier())
    }
}

struct KeyboardAwareModifier: ViewModifier {
    @State private var keyboardHeight: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .padding(.bottom, keyboardHeight)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        keyboardHeight = keyboardFrame.cgRectValue.height
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    keyboardHeight = 0
                }
            }
    }
}