import SwiftUI
import UIKit

// MARK: - Preference

enum GlassPreference {
    static let storageKey = "codex.useLiquidGlass"

    static var isSupported: Bool {
        if #available(iOS 26, *) { return true }
        return false
    }
}

// MARK: - Glass effect modifier

private struct AdaptiveGlassModifier<S: Shape>: ViewModifier {
    @AppStorage(GlassPreference.storageKey) private var glassEnabled = true
    let style: AdaptiveGlassStyle
    let shape: S

    func body(content: Content) -> some View {
        if glassEnabled {
            content.nativeGlassIfAvailable(in: shape) {
                fallbackGlass(for: content)
            }
        } else {
            fallbackGlass(for: content)
        }
    }

    @ViewBuilder
    private func fallbackGlass(for content: Content) -> some View {
        switch style {
        case .regular:
            content
                .background(VisualEffectBlur(style: .systemThinMaterial).clipShape(shape))
        case .toolbarControl:
            content
                .background(VisualEffectBlur(style: .systemUltraThinMaterial).clipShape(shape))
                .overlay(shape.stroke(Color.white.opacity(0.28), lineWidth: 0.7))
                .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
                .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
        }
    }
}

// MARK: - Navigation bar modifier

private struct AdaptiveNavigationBarModifier: ViewModifier {
    @AppStorage(GlassPreference.storageKey) private var glassEnabled = true

    func body(content: Content) -> some View {
        if #available(iOS 26, *), glassEnabled {
            content
        } else {
            content
        }
    }
}

// MARK: - Toolbar item glass mimic

private struct AdaptiveToolbarItemModifier<S: Shape>: ViewModifier {
    @AppStorage(GlassPreference.storageKey) private var glassEnabled = true
    let shape: S

    func body(content: Content) -> some View {
        if glassEnabled {
            content.nativeGlassIfAvailable(in: shape) {
                fallbackGlass(for: content)
            }
        } else {
            fallbackGlass(for: content)
        }
    }

    private func fallbackGlass(for content: Content) -> some View {
        content
            .background(VisualEffectBlur(style: .systemUltraThinMaterial).clipShape(shape))
            .overlay(shape.stroke(Color.white.opacity(0.28), lineWidth: 0.7))
            .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
            .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
    }
}

private struct VisualEffectBlur: UIViewRepresentable {
    let style: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

private extension View {
    @ViewBuilder
    func nativeGlassIfAvailable<S: Shape, Fallback: View>(
        in shape: S,
        @ViewBuilder fallback: () -> Fallback
    ) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            // If building with an older SDK that does not define `glassEffect`,
            // comment this line and leave `fallback()` below as the only branch.
            self.glassEffect(.regular, in: shape)
        } else {
            fallback()
        }
        #else
        fallback()
        #endif
    }
}

// MARK: - View extensions

enum AdaptiveGlassStyle {
    case regular
    case toolbarControl
}

extension View {
    func adaptiveGlass(_ style: AdaptiveGlassStyle, in shape: some Shape) -> some View {
        modifier(AdaptiveGlassModifier(style: style, shape: shape))
    }

    func adaptiveGlass(in shape: some Shape) -> some View {
        modifier(AdaptiveGlassModifier(style: .regular, shape: shape))
    }

    func adaptiveNavigationBar() -> some View {
        modifier(AdaptiveNavigationBarModifier())
    }

    func adaptiveToolbarItem(in shape: some Shape) -> some View {
        modifier(AdaptiveToolbarItemModifier(shape: shape))
    }
}
