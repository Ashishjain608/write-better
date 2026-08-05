import SwiftUI

// MARK: - C15 Primary button

/// h30 · 0×16 · r9 · `accentFill` · white label (4.56:1) · 1pt inner rim in the
/// signature gradient at α0.5. Hover keeps the fill (contrast-preserving) and adds
/// an outer glow; pressed uses `accentPressed`; disabled drops to `surfaceRaised`.
struct PrimaryButtonStyle: ButtonStyle {
    var minWidth: CGFloat = 76

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, minWidth: minWidth)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let minWidth: CGFloat

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .textStyle(.button)
                .foregroundStyle(isEnabled ? Color.white : Theme.Color.textDisabled)
                .padding(.horizontal, Theme.Space.xl)
                .frame(minWidth: minWidth, minHeight: 30)
                .background(fill, in: shape)
                .overlay(rim)
                .shadow(color: glowColor, radius: isHovering && isEnabled ? 12 : 0)
                .scaleEffect(scale)
                .animation(Theme.Motion.curve(.easeOut(duration: 0.09), reduceMotion: reduceMotion),
                           value: configuration.isPressed)
                .animation(Theme.Motion.curve(.easeOut(duration: 0.12), reduceMotion: reduceMotion),
                           value: isHovering)
                .onHover { isHovering = $0 }
                .contentShape(shape)
        }

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        }

        private var fill: Color {
            guard isEnabled else { return Theme.Color.surfaceRaised }
            return configuration.isPressed ? Theme.Color.accentPressed : Theme.Color.accentFill
        }

        @ViewBuilder
        private var rim: some View {
            if isEnabled {
                shape.strokeBorder(Theme.Gradient.signature.opacity(0.5), lineWidth: 1)
            } else {
                shape.strokeBorder(Theme.Color.stroke, lineWidth: 1)
            }
        }

        private var glowColor: Color {
            isHovering && isEnabled ? Theme.Color.accent.opacity(0.35) : .clear
        }

        /// M12 is dropped under Reduce Motion; the pressed fill carries the meaning.
        private var scale: CGFloat {
            guard !reduceMotion, isEnabled else { return 1 }
            if configuration.isPressed { return 0.97 }
            return isHovering ? 1.02 : 1
        }
    }
}

// MARK: - C14 Secondary button

/// h30 · 0×14 · r9 · `surfaceRaised` + hairline · `textPrimary` label.
struct SecondaryButtonStyle: ButtonStyle {
    var role: Role = .neutral
    var minWidth: CGFloat = 0

    enum Role {
        case neutral
        case danger
    }

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, role: role, minWidth: minWidth)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let role: Role
        let minWidth: CGFloat

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .textStyle(.button)
                .foregroundStyle(labelColor)
                .padding(.horizontal, 14)
                .frame(minWidth: minWidth, minHeight: 30)
                .background(fill, in: shape)
                .overlay(shape.strokeBorder(strokeColor, lineWidth: 1))
                .scaleEffect(!reduceMotion && configuration.isPressed && isEnabled ? 0.97 : 1)
                .animation(Theme.Motion.curve(.easeOut(duration: 0.12), reduceMotion: reduceMotion),
                           value: isHovering)
                .animation(Theme.Motion.curve(.easeOut(duration: 0.09), reduceMotion: reduceMotion),
                           value: configuration.isPressed)
                .onHover { isHovering = $0 }
                .contentShape(shape)
        }

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        }

        private var labelColor: Color {
            guard isEnabled else { return Theme.Color.textDisabled }
            return role == .danger ? Theme.Color.danger : Theme.Color.textPrimary
        }

        private var fill: Color {
            guard isEnabled else { return Theme.Color.surfaceRaised.opacity(0.5) }
            if configuration.isPressed { return Theme.Color.surfaceHover }
            return isHovering ? Theme.Color.surfaceHover : Theme.Color.surfaceRaised
        }

        private var strokeColor: Color {
            role == .danger
                ? Theme.Color.danger.opacity(0.45)
                : Theme.Color.stroke(reduceTransparency: reduceTransparency)
        }
    }
}

// MARK: - C10 Quick-action chip

struct ChipButtonStyle: ButtonStyle {
    var isSelected: Bool = false
    var height: CGFloat = 34
    var radius: CGFloat = Theme.Radius.chip

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, isSelected: isSelected, height: height, radius: radius)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let isSelected: Bool
        let height: CGFloat
        let radius: CGFloat

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .textStyle(.button)
                .foregroundStyle(labelColor)
                .padding(.horizontal, Theme.Space.lg)
                .frame(minHeight: height)
                .background(fill, in: shape)
                .overlay(shape.strokeBorder(strokeColor, lineWidth: isSelected ? 1 : 1))
                .scaleEffect(!reduceMotion && configuration.isPressed && isEnabled ? 0.97 : 1)
                // M11: `.easeOut`, deliberately not a spring.
                .animation(Theme.Motion.curve(.easeOut(duration: 0.12), reduceMotion: reduceMotion),
                           value: isHovering)
                .animation(Theme.Motion.curve(.easeOut(duration: 0.16), reduceMotion: reduceMotion),
                           value: isSelected)
                .onHover { isHovering = $0 }
                .contentShape(shape)
        }

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
        }

        private var labelColor: Color {
            guard isEnabled else { return Theme.Color.textDisabled }
            return isSelected ? Theme.Color.accentText : Theme.Color.textPrimary
        }

        private var fill: Color {
            if isSelected { return Theme.Color.accentMuted }
            if !isEnabled { return Theme.Color.surfaceRaised }
            return isHovering ? Theme.Color.surfaceHover : Theme.Color.surfaceRaised
        }

        private var strokeColor: Color {
            if isSelected { return Theme.Color.accent.opacity(0.55) }
            return isHovering
                ? Theme.Color.strokeStrong(reduceTransparency: reduceTransparency)
                : Theme.Color.stroke(reduceTransparency: reduceTransparency)
        }
    }
}

// MARK: - C4 Icon button

/// A glyph in a circular `surfaceRaised` well, hit target padded to 28×28.
struct IconButtonStyle: ButtonStyle {
    var diameter: CGFloat = 24
    var glyphSize: CGFloat = 11

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, diameter: diameter, glyphSize: glyphSize)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let diameter: CGFloat
        let glyphSize: CGFloat

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundStyle(isHovering ? Theme.Color.textPrimary : Theme.Color.textTertiary)
                .frame(width: diameter, height: diameter)
                .background(isHovering ? Theme.Color.surfaceHover : Theme.Color.surfaceRaised, in: Circle())
                .scaleEffect(!reduceMotion && configuration.isPressed ? 0.94 : 1)
                .animation(Theme.Motion.curve(.easeOut(duration: 0.12), reduceMotion: reduceMotion),
                           value: isHovering)
                .onHover { isHovering = $0 }
                .minimumHitTarget()
                .opacity(isEnabled ? 1 : 0.5)
        }
    }
}

// MARK: - C13 Keycap + hint

/// A single keyboard glyph in a 5pt-radius well.
struct Keycap: View {
    let symbol: String

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Text(symbol)
            .textStyle(.keycap)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Theme.Color.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.keycap, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.keycap, style: .continuous)
                    .strokeBorder(Theme.Color.stroke(reduceTransparency: reduceTransparency), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

/// `⌘R redo` — keycap plus its caption, as one accessible element.
struct KeyHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Keycap(symbol: key)
            Text(label).textStyle(.caption)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(key)")
    }
}

// MARK: - C5 Section header

/// Uppercased in the view layer, never in the string constant (§4).
struct SectionHeader<Trailing: View>: View {
    private let title: String
    private let trailing: Trailing

    init(title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.md) {
            Text(title.uppercased()).textStyle(.sectionHeader)
            Spacer(minLength: Theme.Space.md)
            trailing
        }
        .frame(minHeight: 18)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}

// MARK: - C9 Status pill

/// Semantic colour is always paired with a glyph so it survives colour-blindness
/// (§3.4 rule 3).
struct StatusPill: View {
    let text: String
    let tint: Color
    var systemImage: String?
    var showsDot: Bool = false

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            if showsDot {
                Circle().fill(tint).frame(width: 6, height: 6)
            }
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(text.uppercased()).textStyle(.badge)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.xs)
        .background(tint.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

// MARK: - M4 Skeleton

/// 3 shimmer bars at 92% / 78% / 46%, height 10, radius 5, gap 10, sweeping
/// left→right on a 1400 ms linear loop. Under Reduce Motion the bars stay but the
/// sweep stops — "loading" is still conveyed (§10).
struct SkeletonLines: View {
    var widths: [Double] = [0.92, 0.78, 0.46]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(widths.enumerated()), id: \.offset) { _, fraction in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(barColor)
                        .frame(width: max(12, geo.size.width * fraction), height: 10)
                }
            }
            .overlay(sweep(width: geo.size.width))
            .mask(
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(widths.enumerated()), id: \.offset) { _, fraction in
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .frame(width: max(12, geo.size.width * fraction), height: 10)
                    }
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: CGFloat(widths.count) * 10 + CGFloat(max(0, widths.count - 1)) * 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Waiting for the first words")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 2
            }
        }
    }

    private var barColor: Color {
        Theme.Color.textPrimary.opacity(reduceTransparency ? 0.14 : 0.06)
    }

    @ViewBuilder
    private func sweep(width: CGFloat) -> some View {
        if !reduceMotion {
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: Theme.Color.textPrimary.opacity(0.10), location: 0.5),
                .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing)
            .frame(width: max(60, width * 0.45))
            .offset(x: phase * width)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Preview

#Preview("Controls") {
    VStack(alignment: .leading, spacing: Theme.Space.xl) {
        HStack(spacing: Theme.Space.lg) {
            Button("Copy") {}.buttonStyle(PrimaryButtonStyle())
            Button("Replace") {}.buttonStyle(SecondaryButtonStyle())
            Button("Remove key") {}.buttonStyle(SecondaryButtonStyle(role: .danger))
            Button("Disabled") {}.buttonStyle(PrimaryButtonStyle()).disabled(true)
        }

        HStack(spacing: Theme.Space.md) {
            Button { } label: { Label("Fix Grammar", systemImage: "text.badge.checkmark") }
                .buttonStyle(ChipButtonStyle())
            Button { } label: { Label("Shorten", systemImage: "scissors") }
                .buttonStyle(ChipButtonStyle(isSelected: true))
            Button { } label: { Image(systemName: "xmark") }
                .buttonStyle(IconButtonStyle())
        }

        HStack(spacing: Theme.Space.lg) {
            KeyHint(key: "esc", label: "close")
            KeyHint(key: "⌘R", label: "redo")
            KeyHint(key: "⌘,", label: "settings")
        }

        HStack(spacing: Theme.Space.md) {
            StatusPill(text: "Streaming", tint: Theme.Color.streaming, showsDot: true)
            StatusPill(text: "Stopped", tint: Theme.Color.warning, systemImage: "exclamationmark.circle.fill")
            StatusPill(text: "Verified", tint: Theme.Color.success, systemImage: "checkmark.circle.fill")
        }

        SectionHeader(title: "Improved") {
            Text("+14 wds").textStyle(.caption).monospacedDigit()
        }

        SkeletonLines()
            .padding(Theme.Space.lg)
            .sunkenSurface()
    }
    .padding(Theme.Space.h1)
    .frame(width: 540)
    .background(Theme.Color.surface)
}
