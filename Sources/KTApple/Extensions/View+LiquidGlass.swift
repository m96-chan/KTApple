import SwiftUI

/// Liquid Glass (macOS 26 Tahoe) adoption helpers.
///
/// The app deploys to macOS 15, where the Liquid Glass APIs do not exist.
/// Every call site therefore goes through these wrappers, which apply the real
/// glass on Tahoe and fall back to the pre-Tahoe material/fill styling below it.
///
/// Standard AppKit/SwiftUI controls (Form, Slider, NSMenu, …) pick up Liquid Glass
/// automatically because the app is built against the macOS 26 SDK — only the
/// custom-drawn surfaces in the tile editor and the drop overlay need these.

@available(macOS 26.0, *)
private func makeGlass(clear: Bool, tint: Color?, interactive: Bool) -> Glass {
    var glass: Glass = clear ? .clear : .regular
    if let tint {
        glass = glass.tint(tint)
    }
    if interactive {
        glass = glass.interactive()
    }
    return glass
}

extension View {
    /// Place the view on a Liquid Glass surface on macOS 26+.
    ///
    /// On macOS 15 the same `shape` is filled with `fallback` instead, so the
    /// layout is identical on both systems and only the material differs.
    @ViewBuilder
    func glassSurface(
        in shape: some Shape,
        clear: Bool = false,
        tint: Color? = nil,
        interactive: Bool = false,
        fallback: some ShapeStyle
    ) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(makeGlass(clear: clear, tint: tint, interactive: interactive), in: shape)
        } else {
            background(shape.fill(fallback))
        }
    }

    /// `.glass` button style on macOS 26+, `.bordered` on earlier systems.
    @ViewBuilder
    func glassButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    /// Emphasised variant for the default action of a group.
    ///
    /// `.glassProminent` on macOS 26+, `.borderedProminent` on earlier systems.
    @ViewBuilder
    func glassProminentButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}

/// Groups nearby glass surfaces so Tahoe can merge and batch-render them.
///
/// Renders as a plain pass-through on macOS 15.
struct GlassContainer<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
