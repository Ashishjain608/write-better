import SwiftUI
import AppKit

// MARK: - NSVisualEffectView bridge (§5.4 layer 1, §11.1)

/// SwiftUI's `.ultraThinMaterial` does **not** reliably sample behind a borderless
/// `NSPanel` (§11.2 pitfall 8), so the panel's blur comes from a real
/// `NSVisualEffectView` in `.behindWindow` blending mode.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var isEmphasized: Bool = true

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = isEmphasized
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        // Materials are never animated (§6 "never animate"), only assigned.
        if view.material != material { view.material = material }
        if view.blendingMode != blendingMode { view.blendingMode = blendingMode }
        view.isEmphasized = isEmphasized
        view.state = .active
    }
}

// MARK: - The glass recipe (§5.4)

/// The five-layer panel background, expressed once so no `#available` checks are
/// scattered through the views (§11.1).
///
/// macOS 14 path: `NSVisualEffectView` → tint → vignette → rim → outer edge.
/// macOS 26 path: `.glassEffect(.regular, in:)` replaces layers 1–3 and the rim
/// alphas are halved, because the system already draws one.
///
/// Under Reduce Transparency layers 1–3 are skipped entirely for an opaque
/// `surface` fill (§10).
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = Theme.Radius.panel
    /// 0…1 — how much extra light the rim carries. Driven by M7 while streaming.
    var rimAccent: Double = 0
    /// Accent tint bled into the rim while streaming.
    var rimTint: Color = Theme.Color.accent

    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    /// The app's own "Reduce visual effects" switch, for users who want the opaque
    /// panel without turning the system setting on globally.
    @AppStorage("reduceVisualEffects") private var appReduceTransparency = false

    private var reduceTransparency: Bool { systemReduceTransparency || appReduceTransparency }

    func body(content: Content) -> some View {
        content
            .background(background)
            .clipShape(shape)
            .overlay(rim)
            .overlay(outerEdge)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    @ViewBuilder
    private var background: some View {
        if reduceTransparency {
            // Layers 1–3 dropped; one opaque fill.
            Theme.Color.surface
        } else if #available(macOS 26.0, *) {
            // Layers 1–3 become one system glass surface. Nothing inside the panel
            // may be glass too — "glass cannot sample other glass".
            LiquidGlassBackground(cornerRadius: cornerRadius)
        } else {
            ZStack {
                VisualEffectBackground()     // 1
                Theme.Color.surfaceTint      // 2 — surface @0.72 dark / @0.82 light
                Theme.Gradient.vignette      // 3
            }
        }
    }

    private var rim: some View {                               // 4
        shape
            .strokeBorder(Theme.Gradient.rim(accentBoost: rimBoost), lineWidth: rimWidth)
            .overlay(
                shape
                    .strokeBorder(rimTint.opacity(rimAccent), lineWidth: rimWidth)
            )
            .allowsHitTesting(false)
    }

    private var outerEdge: some View {                          // 5
        shape
            .strokeBorder(Theme.Color.make(Theme.Color.hex(0x000000, 0.60),
                                           Theme.Color.hex(0x000000, 0.18)),
                          lineWidth: 0.5)
            .padding(-0.5)
            .allowsHitTesting(false)
    }

    /// macOS 26 draws its own rim, so ours drops to half strength.
    private var rimWidth: CGFloat {
        if #available(macOS 26.0, *), !reduceTransparency { return 0.5 }
        return 1
    }

    private var rimBoost: Double { 0 }
}

/// Isolated so the `@available` attribute lives on exactly one type.
@available(macOS 26.0, *)
private struct LiquidGlassBackground: View {
    let cornerRadius: CGFloat
    var body: some View {
        // `glassEffect` ships in macOS 26; the panel is the app's *only* glass
        // layer, so a single container is enough.
        Color.clear
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Elevation helpers

/// `e1` — the Raycast rule: depth from the surface ladder + a hairline, no shadow.
struct CardSurface: ViewModifier {
    var radius: CGFloat = Theme.Radius.card
    var fill: Color = Theme.Color.surfaceRaised
    var strokeColor: Color? = nil
    var lineWidth: CGFloat = 1

    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @AppStorage("reduceVisualEffects") private var appReduceTransparency = false

    private var reduceTransparency: Bool { systemReduceTransparency || appReduceTransparency }

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(strokeColor ?? Theme.Color.stroke(reduceTransparency: reduceTransparency),
                                  lineWidth: lineWidth)
            )
    }
}

/// `e2` — raised popovers and menus: strong hairline plus one shadow.
struct RaisedSurface: ViewModifier {
    var radius: CGFloat = Theme.Radius.card
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background(Theme.Color.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.Color.strokeStrong(reduceTransparency: reduceTransparency), lineWidth: 1)
            )
            .shadow(Theme.Shadow.e2)
    }
}

extension View {
    func glassSurface(cornerRadius: CGFloat = Theme.Radius.panel,
                      rimAccent: Double = 0,
                      rimTint: Color = Theme.Color.accent) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, rimAccent: rimAccent, rimTint: rimTint))
    }

    /// e1 card: `surfaceRaised` + hairline, no shadow.
    func cardSurface(radius: CGFloat = Theme.Radius.card,
                     fill: Color = Theme.Color.surfaceRaised,
                     stroke: Color? = nil,
                     lineWidth: CGFloat = 1) -> some View {
        modifier(CardSurface(radius: radius, fill: fill, strokeColor: stroke, lineWidth: lineWidth))
    }

    /// e1 sunken well: text fields, the source strip, the result canvas.
    func sunkenSurface(radius: CGFloat = Theme.Radius.card,
                       stroke: Color? = nil,
                       lineWidth: CGFloat = 1) -> some View {
        modifier(CardSurface(radius: radius, fill: Theme.Color.surfaceSunken,
                             strokeColor: stroke, lineWidth: lineWidth))
    }

    func raisedSurface(radius: CGFloat = Theme.Radius.card) -> some View {
        modifier(RaisedSurface(radius: radius))
    }
}

// MARK: - Preview

#Preview("Surfaces") {
    VStack(spacing: Theme.Space.xl) {
        Text("Glass panel")
            .textStyle(.title)
            .frame(width: 320, height: 120)
            .glassSurface()

        Text("Streaming rim (M7 at peak)")
            .textStyle(.body)
            .frame(width: 320, height: 90)
            .glassSurface(rimAccent: 0.45, rimTint: Theme.Color.streaming)

        HStack(spacing: Theme.Space.lg) {
            Text("e1 card").textStyle(.label).padding(Theme.Space.lg).cardSurface()
            Text("sunken").textStyle(.label).padding(Theme.Space.lg).sunkenSurface()
            Text("e2").textStyle(.label).padding(Theme.Space.lg).raisedSurface()
        }
    }
    .padding(Theme.Space.h2)
    .frame(width: 460, height: 460)
    .background(Theme.Color.bgBase)
}
