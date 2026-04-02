//
//  LiquidGlassSupport.swift
//  LanRead
//
//  Created by Codex on 2026/4/1.
//

import SwiftUI

extension View {
    /// Wrap related views in one glass rendering group on iOS 26+.
    @ViewBuilder
    func lanReadGlassGroup(spacing: CGFloat = 24) -> some View {
        #if swift(>=6.2)
        if #available(iOS 26, *) {
            LanReadGlassGroup(spacing: spacing) {
                self
            }
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Apply Liquid Glass surface with iOS 16+ material fallback.
    @ViewBuilder
    func lanReadGlassSurface(
        cornerRadius: CGFloat = 14,
        interactive: Bool = false,
        tint: Color? = nil
    ) -> some View {
        #if swift(>=6.2)
        if #available(iOS 26, *) {
            if interactive {
                if let tint {
                    self.glassEffect(
                        .regular.tint(tint).interactive(),
                        in: .rect(cornerRadius: cornerRadius)
                    )
                } else {
                    self.glassEffect(
                        .regular.interactive(),
                        in: .rect(cornerRadius: cornerRadius)
                    )
                }
            } else {
                if let tint {
                    self.glassEffect(
                        .regular.tint(tint),
                        in: .rect(cornerRadius: cornerRadius)
                    )
                } else {
                    self.glassEffect(
                        .regular,
                        in: .rect(cornerRadius: cornerRadius)
                    )
                }
            }
        } else {
            lanReadFallbackSurface(cornerRadius: cornerRadius)
        }
        #else
        lanReadFallbackSurface(cornerRadius: cornerRadius)
        #endif
    }

    /// Apply a Liquid Glass button style on iOS 26+, with bordered fallback.
    @ViewBuilder
    func lanReadGlassButtonStyle(prominent: Bool = false) -> some View {
        #if swift(>=6.2)
        if #available(iOS 26, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else {
            lanReadFallbackButtonStyle(prominent: prominent)
        }
        #else
        lanReadFallbackButtonStyle(prominent: prominent)
        #endif
    }

    private func lanReadFallbackSurface(cornerRadius: CGFloat) -> some View {
        background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }

    @ViewBuilder
    private func lanReadFallbackButtonStyle(prominent: Bool) -> some View {
        if prominent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }
}

#if swift(>=6.2)
@available(iOS 26, *)
private struct LanReadGlassGroup<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content
        }
    }
}
#endif
