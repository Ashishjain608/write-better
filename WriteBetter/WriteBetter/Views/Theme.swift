import SwiftUI
import AppKit

/// The single source of truth for every colour, size, font, radius, shadow and
/// animation curve in WriteBetter.
///
/// Token names and values come verbatim from `DESIGN-BRIEF.md` (§3–§6, Appendix A).
/// **Nothing outside this file may hardcode a colour.**
///
/// Every colour resolves through `NSColor(name:dynamicProvider:)`, so light/dark —
/// and macOS's *Increase Contrast* setting, which surfaces as the
/// `accessibilityHighContrast*` appearances — switch automatically without any
/// view branching on `colorScheme`.
enum Theme {

    // MARK: - Colour (§3, Appendix A)

    enum Color {

        // Surfaces
        static let bgBase        = make(hex(0x070910), hex(0xF0F1F5))
        static let surface       = make(hex(0x0E1118), hex(0xFFFFFF))
        static let surfaceRaised = make(hex(0x161A24), hex(0xFFFFFF))
        static let surfaceSunken = make(hex(0x0B0E15), hex(0xF4F5F9))
        static let surfaceHover  = make(hex(0x1D2230), hex(0xEDEFF4))

        // Strokes. Under *Increase Contrast* each is promoted one rung (§3.4 rule 4).
        static let stroke = make(hex(0xFFFFFF, 0.09), hex(0x000000, 0.10),
                                 hcDark: hex(0xFFFFFF, 0.18), hcLight: hex(0x000000, 0.18))
        static let strokeStrong = make(hex(0xFFFFFF, 0.18), hex(0x000000, 0.18),
                                       hcDark: hex(0xFFFFFF, 0.34), hcLight: hex(0x000000, 0.34))
        /// Top stop of the panel's rim gradient (§5.4 layer 4).
        static let strokeGlass = make(hex(0xFFFFFF, 0.28), hex(0xFFFFFF, 0.70))

        /// Reduce-Transparency variants (§10): 0.09 → 0.16, 0.18 → 0.30.
        private static let strokeOpaque = make(hex(0xFFFFFF, 0.16), hex(0x000000, 0.16),
                                               hcDark: hex(0xFFFFFF, 0.26), hcLight: hex(0x000000, 0.26))
        private static let strokeStrongOpaque = make(hex(0xFFFFFF, 0.30), hex(0x000000, 0.30),
                                                     hcDark: hex(0xFFFFFF, 0.42), hcLight: hex(0x000000, 0.42))

        static func stroke(reduceTransparency: Bool) -> SwiftUI.Color {
            reduceTransparency ? strokeOpaque : stroke
        }
        static func strokeStrong(reduceTransparency: Bool) -> SwiftUI.Color {
            reduceTransparency ? strokeStrongOpaque : strokeStrong
        }

        // Text ramp
        static let textPrimary   = make(hex(0xF2F4F8), hex(0x14161C))
        static let textSecondary = make(hex(0xA8B0BF), hex(0x4E5666))
        /// Promoted to `textSecondary` under Increase Contrast (§3.4 rule 4).
        static let textTertiary  = make(hex(0x8A93A6), hex(0x6D7587),
                                        hcDark: hex(0xA8B0BF), hcLight: hex(0x4E5666))
        /// Disabled controls **only** — never used to carry information (§10).
        static let textDisabled  = make(hex(0x6E7789), hex(0x9AA1B0))

        // Accent
        static let accent            = make(hex(0x7C6BFF), hex(0x5B45E0))
        static let accentText        = make(hex(0x9A8CFF), hex(0x5B45E0))
        static let accentFill        = make(hex(0x6E5BFF), hex(0x5B45E0))
        static let accentPressed     = make(hex(0x5B45E0), hex(0x4A35C7))
        static let accentMuted       = make(hex(0x7C6BFF, 0.16), hex(0x5B45E0, 0.10))
        static let accentGradientEnd = make(hex(0x37D3E8), hex(0x1596AC))

        // Semantic
        static let streaming = make(hex(0x37D3E8), hex(0x0E7C8C))
        static let success   = make(hex(0x3DDC97), hex(0x0B7A56))
        static let warning   = make(hex(0xF5B841), hex(0x8A5200))
        static let danger    = make(hex(0xFF8080), hex(0xC62828))

        static let diffAddBg = make(hex(0x3DDC97, 0.14), hex(0x0B7A56, 0.12))
        static let diffDelBg = make(hex(0xFF8080, 0.14), hex(0xC62828, 0.12))
        static let scrim     = make(hex(0x000000, 0.45), hex(0x000000, 0.20))

        /// Footer-rail wash (C12).
        static let railWash = make(hex(0x000000, 0.14), hex(0x000000, 0.03))

        /// §5.4 layer 2 — the tint that sits over the blur: `surface` @0.72 dark, @0.82 light.
        static let surfaceTint = make(hex(0x0E1118, 0.72), hex(0xFFFFFF, 0.82))

        // MARK: Construction

        static func hex(_ value: UInt32, _ alpha: Double = 1) -> NSColor {
            NSColor(srgbRed: Double((value >> 16) & 0xFF) / 255,
                    green: Double((value >> 8) & 0xFF) / 255,
                    blue: Double(value & 0xFF) / 255,
                    alpha: alpha)
        }

        /// Builds an appearance-reactive colour. `hcDark`/`hcLight` default to the
        /// standard values when a token needs no Increase-Contrast promotion.
        static func make(_ dark: NSColor, _ light: NSColor,
                         hcDark: NSColor? = nil, hcLight: NSColor? = nil) -> SwiftUI.Color {
            let highContrastDark = hcDark ?? dark
            let highContrastLight = hcLight ?? light
            return SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
                switch appearance.bestMatch(from: [.aqua, .darkAqua,
                                                   .accessibilityHighContrastAqua,
                                                   .accessibilityHighContrastDarkAqua]) {
                case .some(.darkAqua):                          return dark
                case .some(.accessibilityHighContrastDarkAqua):  return highContrastDark
                case .some(.accessibilityHighContrastAqua):      return highContrastLight
                default:                                         return light
                }
            })
        }
    }

    // MARK: - Gradient (§3.1)

    enum Gradient {
        /// `accent → accentGradientEnd`, topLeading → bottomTrailing.
        /// Never on text, never as a full-panel background.
        static var signature: LinearGradient {
            LinearGradient(colors: [Color.accent, Color.accentGradientEnd],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }

        /// §5.4 layer 4 — the rim highlight that actually sells the glass.
        static func rim(accentBoost: Double = 0) -> LinearGradient {
            LinearGradient(stops: [
                .init(color: Color.make(Color.hex(0xFFFFFF, 0.28 + accentBoost),
                                        Color.hex(0xFFFFFF, 0.85)), location: 0.00),
                .init(color: Color.make(Color.hex(0xFFFFFF, 0.10 + accentBoost * 0.6),
                                        Color.hex(0xFFFFFF, 0.40)), location: 0.22),
                .init(color: Color.make(Color.hex(0xFFFFFF, 0.04), Color.hex(0x000000, 0.06)),
                      location: 0.55),
                .init(color: Color.make(Color.hex(0xFFFFFF, 0.02), Color.hex(0x000000, 0.10)),
                      location: 1.00),
            ], startPoint: .top, endPoint: .bottom)
        }

        /// §5.4 layer 3 — the top-down vignette.
        static var vignette: LinearGradient {
            LinearGradient(stops: [
                .init(color: Color.make(Color.hex(0xFFFFFF, 0.05), Color.hex(0xFFFFFF, 0.20)), location: 0.00),
                .init(color: SwiftUI.Color.clear, location: 0.30),
                .init(color: SwiftUI.Color.clear, location: 0.60),
                .init(color: Color.make(Color.hex(0x000000, 0.14), Color.hex(0x000000, 0.04)), location: 1.00),
            ], startPoint: .top, endPoint: .bottom)
        }
    }

    // MARK: - Radius (§5.2)

    enum Radius {
        static let panel: CGFloat = 18
        static let window: CGFloat = 12
        static let card: CGFloat = 12
        static let control: CGFloat = 9
        static let chip: CGFloat = 8
        static let keycap: CGFloat = 5
    }

    // MARK: - Space (§5.1)

    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 20
        static let h1: CGFloat = 24
        static let h2: CGFloat = 32
        static let h3: CGFloat = 40
    }

    // MARK: - Font (§4)

    enum Font {
        static let displayTitle  = SwiftUI.Font.system(size: 22, weight: .semibold)
        static let title         = SwiftUI.Font.system(size: 17, weight: .semibold)
        static let subtitle      = SwiftUI.Font.system(size: 13, weight: .regular)
        static let sectionHeader = SwiftUI.Font.system(size: 11, weight: .semibold)
        static let result        = SwiftUI.Font.system(size: 14, weight: .regular)
        static let source        = SwiftUI.Font.system(size: 12, weight: .regular)
        static let body          = SwiftUI.Font.system(size: 13, weight: .regular)
        static let label         = SwiftUI.Font.system(size: 12, weight: .medium)
        static let button        = SwiftUI.Font.system(size: 12, weight: .semibold)
        static let caption       = SwiftUI.Font.system(size: 11, weight: .regular)
        static let keycap        = SwiftUI.Font.system(size: 10, weight: .medium, design: .monospaced)
        static let mono          = SwiftUI.Font.system(size: 12, weight: .regular, design: .monospaced)
        static let badge         = SwiftUI.Font.system(size: 10, weight: .semibold)
    }

    /// Font + tracking + line-spacing + default colour, applied as one unit via
    /// `View.textStyle(_:)`. Line spacing is `lineHeight − ceil(size × 1.19)` per §4.
    enum TextStyle: CaseIterable {
        case displayTitle, title, subtitle, sectionHeader, result, source
        case body, label, button, caption, keycap, mono, badge

        var font: SwiftUI.Font {
            switch self {
            case .displayTitle:  return Font.displayTitle
            case .title:         return Font.title
            case .subtitle:      return Font.subtitle
            case .sectionHeader: return Font.sectionHeader
            case .result:        return Font.result
            case .source:        return Font.source
            case .body:          return Font.body
            case .label:         return Font.label
            case .button:        return Font.button
            case .caption:       return Font.caption
            case .keycap:        return Font.keycap
            case .mono:          return Font.mono
            case .badge:         return Font.badge
            }
        }

        var tracking: CGFloat {
            switch self {
            case .displayTitle:  return -0.30
            case .title:         return -0.20
            case .subtitle:      return 0
            case .sectionHeader: return 0.60
            case .result:        return 0
            case .source:        return 0
            case .body:          return -0.05
            case .label:         return 0
            case .button:        return 0.10
            case .caption:       return 0.10
            case .keycap:        return 0.20
            case .mono:          return 0
            case .badge:         return 0.40
            }
        }

        var lineSpacing: CGFloat {
            switch self {
            case .displayTitle:  return 1
            case .title:         return 1
            case .subtitle:      return 2
            case .sectionHeader: return 0
            case .result:        return 4
            case .source:        return 2
            case .body:          return 2
            case .label:         return 1
            case .button:        return 1
            case .caption:       return 0
            case .keycap:        return 0
            case .mono:          return 1
            case .badge:         return 0
            }
        }

        /// `nil` means "inherit whatever the caller set".
        var color: SwiftUI.Color? {
            switch self {
            case .displayTitle, .title, .result, .label, .mono: return Color.textPrimary
            case .subtitle, .source, .body:                     return Color.textSecondary
            case .sectionHeader, .caption, .keycap:             return Color.textTertiary
            case .button, .badge:                               return nil
            }
        }
    }

    // MARK: - Motion (§6)

    enum Motion {
        static let instant   = Animation.easeOut(duration: 0.12)
        static let quick     = Animation.easeOut(duration: 0.16)
        static let standard  = Animation.easeInOut(duration: 0.22)
        static let enter     = Animation.spring(response: 0.28, dampingFraction: 0.86)
        static let celebrate = Animation.spring(response: 0.26, dampingFraction: 0.62)
        /// What every curve collapses to under Reduce Motion.
        static let reduced   = Animation.easeInOut(duration: 0.12)

        /// The Reduce-Motion-aware wrapper every view uses.
        static func curve(_ base: Animation, reduceMotion: Bool) -> Animation {
            reduceMotion ? reduced : base
        }

        /// A repeating curve becomes a *static* value under Reduce Motion, so
        /// callers get `nil` and skip the animation entirely (M4/M6/M7/M20).
        static func repeating(_ base: Animation, reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : base
        }
    }

    // MARK: - Shadow (§5.3)

    /// Light-appearance alphas are 0.45× the dark ones, expressed through the
    /// dynamic colour rather than a `colorScheme` branch in view code.
    struct ShadowSpec {
        let color: SwiftUI.Color
        let radius: CGFloat
        let y: CGFloat
    }

    enum Shadow {
        static let e2 = ShadowSpec(color: Color.make(Color.hex(0x000000, 0.35), Color.hex(0x000000, 0.16)),
                                   radius: 20, y: 8)
        /// e3 is two shadows; `e3` is the large one, `e3Contact` the tight one.
        static let e3 = ShadowSpec(color: Color.make(Color.hex(0x000000, 0.55), Color.hex(0x000000, 0.25)),
                                   radius: 44, y: 18)
        static let e3Contact = ShadowSpec(color: Color.make(Color.hex(0x000000, 0.30), Color.hex(0x000000, 0.14)),
                                          radius: 10, y: 3)
        static let glow = ShadowSpec(color: Color.accent.opacity(0.30), radius: 28, y: 0)
    }
}

// MARK: - View sugar

extension View {

    /// Applies a §4 text style as one unit (font + tracking + line spacing + colour).
    func textStyle(_ style: Theme.TextStyle) -> some View {
        modifier(TextStyleModifier(style: style))
    }

    func shadow(_ spec: Theme.ShadowSpec) -> some View {
        shadow(color: spec.color, radius: spec.radius, x: 0, y: spec.y)
    }

    /// The §10 focus ring: 2pt accent, drawn *outside* the control at +2pt,
    /// radius = control radius + 2, animated per M17.
    func focusRing(_ isFocused: Bool, radius: CGFloat, reduceMotion: Bool = false) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius + 2, style: .continuous)
                .strokeBorder(Theme.Color.accent, lineWidth: isFocused ? 2 : 0)
                .padding(-2)
                .opacity(isFocused ? 1 : 0)
                .animation(Theme.Motion.curve(.easeOut(duration: 0.10), reduceMotion: reduceMotion),
                           value: isFocused)
        )
    }

    /// Guarantees the §5.1 minimum 28×28 hit target for small glyphs.
    func minimumHitTarget(_ size: CGFloat = 28) -> some View {
        frame(minWidth: size, minHeight: size)
            .contentShape(Rectangle())
    }
}

private struct TextStyleModifier: ViewModifier {
    let style: Theme.TextStyle

    func body(content: Content) -> some View {
        let base = content
            .font(style.font)
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing)
        if let color = style.color {
            return AnyView(base.foregroundStyle(color))
        }
        return AnyView(base)
    }
}

// MARK: - Preview

#Preview("Theme tokens") {
    ScrollView {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            Text("TYPE SCALE").textStyle(.sectionHeader)
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Display title").textStyle(.displayTitle)
                Text("Title").textStyle(.title)
                Text("Subtitle — one line under a title").textStyle(.subtitle)
                Text("Result — the hero type of the app").textStyle(.result)
                Text("Source — the captured original").textStyle(.source)
                Text("Body copy in Settings").textStyle(.body)
                Text("Label").textStyle(.label)
                Text("Caption · 128 chars").textStyle(.caption).monospacedDigit()
                Text("sk-ant-api03-abcdef").textStyle(.mono)
            }

            Text("SURFACES").textStyle(.sectionHeader)
            HStack(spacing: Theme.Space.md) {
                ForEach(Array([("base", Theme.Color.bgBase), ("surface", Theme.Color.surface),
                               ("raised", Theme.Color.surfaceRaised), ("sunken", Theme.Color.surfaceSunken),
                               ("hover", Theme.Color.surfaceHover)].enumerated()), id: \.offset) { _, pair in
                    VStack(spacing: Theme.Space.xs) {
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .fill(pair.1)
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                .strokeBorder(Theme.Color.stroke, lineWidth: 1))
                            .frame(width: 62, height: 44)
                        Text(pair.0).textStyle(.caption)
                    }
                }
            }

            Text("SEMANTIC").textStyle(.sectionHeader)
            HStack(spacing: Theme.Space.md) {
                ForEach(Array([("accent", Theme.Color.accent), ("streaming", Theme.Color.streaming),
                               ("success", Theme.Color.success), ("warning", Theme.Color.warning),
                               ("danger", Theme.Color.danger)].enumerated()), id: \.offset) { _, pair in
                    VStack(spacing: Theme.Space.xs) {
                        Circle().fill(pair.1).frame(width: 28, height: 28)
                        Text(pair.0).textStyle(.caption)
                    }
                }
            }

            Text("SIGNATURE GRADIENT").textStyle(.sectionHeader)
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .fill(Theme.Gradient.signature)
                .frame(height: 34)
        }
        .padding(Theme.Space.h1)
    }
    .frame(width: 520, height: 640)
    .background(Theme.Color.surface)
}
