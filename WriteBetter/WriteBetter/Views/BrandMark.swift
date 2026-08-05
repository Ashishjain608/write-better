import SwiftUI
import AppKit

// MARK: - Geometry (§2.2)

/// "Caret Ascend" — a caret lifting off a baseline bar with a four-point spark.
///
/// All coordinates are the brief's literal 1024 × 1024 **top-left origin** values.
/// SwiftUI `Path` already uses that convention; the AppKit renderer flips the CTM
/// once, at the top, and never mixes the two.
enum MarkGeometry {
    static let canvas: CGFloat = 1024

    /// Layer 2 — returned as a filled outline so it can take a gradient fill.
    static func caret(lineWidth: CGFloat = 104) -> CGPath {
        let line = CGMutablePath()
        line.move(to: CGPoint(x: 296, y: 604))
        line.addLine(to: CGPoint(x: 512, y: 388))
        line.addLine(to: CGPoint(x: 728, y: 604))
        return line.copy(strokingWithWidth: lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
    }

    /// Layer 3 — the baseline bar, a capsule.
    static func bar(height: CGFloat = 68) -> CGPath {
        let rect = CGRect(x: 330, y: 686, width: 364, height: height)
        return CGPath(roundedRect: rect, cornerWidth: height / 2, cornerHeight: height / 2, transform: nil)
    }

    /// Layer 4 — four quadratic Béziers, each tip→tip with its control at the centre.
    static func spark() -> CGPath {
        let centre = CGPoint(x: 762, y: 350)
        let north = CGPoint(x: 762, y: 276)
        let east  = CGPoint(x: 836, y: 350)
        let south = CGPoint(x: 762, y: 424)
        let west  = CGPoint(x: 688, y: 350)

        let path = CGMutablePath()
        path.move(to: north)
        path.addQuadCurve(to: east, control: centre)
        path.addQuadCurve(to: south, control: centre)
        path.addQuadCurve(to: west, control: centre)
        path.addQuadCurve(to: north, control: centre)
        path.closeSubpath()
        return path
    }

    /// Tight box of the in-app glyph (layers 2 + 3 + 4).
    static let glyphBounds = CGRect(x: 244, y: 276, width: 592, height: 478)

    /// Tight box of the menu-bar template (layers 2 + 3, heavier strokes).
    static var templateBounds: CGRect {
        caret(lineWidth: 118).boundingBoxOfPath.union(bar(height: 78).boundingBoxOfPath)
    }
}

/// Maps one of the design-space paths into whatever rect SwiftUI hands it,
/// preserving the glyph's aspect ratio and its position relative to the others.
private struct MarkShape: Shape {
    let source: Path
    let designBounds: CGRect

    init(path: CGPath, designBounds: CGRect) {
        self.source = Path(path)
        self.designBounds = designBounds
    }

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / designBounds.width, rect.height / designBounds.height)
        let transform = CGAffineTransform(translationX: rect.midX - designBounds.midX * scale,
                                          y: rect.midY - designBounds.midY * scale)
            .scaledBy(x: scale, y: scale)
        return source.applying(transform)
    }
}

// MARK: - In-app glyph

/// The full-colour mark used in the panel header, Settings and onboarding.
///
/// Prefers Agent D's `LogoMark` asset; falls back to drawing the same geometry so
/// the app never renders a hole if the asset has not landed yet.
struct BrandMark: View {
    var size: CGFloat = 18

    /// Resolved once — `NSImage(named:)` is cheap but not free, and this sits in a
    /// header that re-renders on every streamed flush.
    private static let asset: NSImage? = NSImage(named: "LogoMark")

    var body: some View {
        Group {
            if let asset = Self.asset {
                Image(nsImage: asset)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                drawn
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var bounds: CGRect { MarkGeometry.glyphBounds }

    private var drawn: some View {
        ZStack {
            MarkShape(path: MarkGeometry.caret(), designBounds: bounds)
                .fill(LinearGradient(stops: [
                    .init(color: .white, location: 0.00),
                    .init(color: Color(red: 0.929, green: 0.922, blue: 1.0), location: 0.55),
                    .init(color: Color(red: 0.725, green: 0.682, blue: 1.0), location: 1.00),
                ], startPoint: .topLeading, endPoint: .bottomTrailing))

            MarkShape(path: MarkGeometry.bar(), designBounds: bounds)
                .fill(Theme.Gradient.signature)

            MarkShape(path: MarkGeometry.spark(), designBounds: bounds)
                .fill(.white)
                .shadow(color: Theme.Color.accentGradientEnd.opacity(0.6),
                        radius: max(0.5, size * 0.05))
        }
    }
}

// MARK: - Menu-bar icon (§7.3)

/// The three status-bar renditions. `MenuBarIcon` from the asset catalog wins when
/// it exists; otherwise the same geometry is drawn at runtime, so the status item
/// is **never** blank.
enum MenuBarIconFactory {

    enum State {
        case ready
        case working
        case needsSetup
    }

    /// Template rendition of the mark (layers 2 + 3, solid black, 8% clear margin).
    static func markImage(size: CGFloat = 18) -> NSImage {
        if let asset = NSImage(named: "MenuBarIcon") {
            let copy = asset.copy() as? NSImage ?? asset
            copy.size = NSSize(width: size, height: size)
            copy.isTemplate = true
            return copy
        }
        return drawTemplate(size: size)
    }

    private static func drawTemplate(size: CGFloat) -> NSImage {
        let bounds = MarkGeometry.templateBounds
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            // One flip, at the top, so the brief's top-left coordinates are literal.
            ctx.translateBy(x: 0, y: rect.height)
            ctx.scaleBy(x: 1, y: -1)

            let inset = rect.width * 0.08
            let target = rect.insetBy(dx: inset, dy: inset)
            let scale = min(target.width / bounds.width, target.height / bounds.height)
            var transform = CGAffineTransform(translationX: target.midX - bounds.midX * scale,
                                              y: target.midY - bounds.midY * scale)
                .scaledBy(x: scale, y: scale)

            let combined = CGMutablePath()
            if let caret = MarkGeometry.caret(lineWidth: 118).copy(using: &transform) {
                combined.addPath(caret)
            }
            if let bar = MarkGeometry.bar(height: 78).copy(using: &transform) {
                combined.addPath(bar)
            }

            ctx.setFillColor(NSColor.black.cgColor)
            ctx.addPath(combined)
            ctx.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The words VoiceOver reads for the status item (§10).
    static func accessibilityLabel(for state: State) -> String {
        switch state {
        case .ready:      return "WriteBetter"
        case .working:    return "WriteBetter, working"
        case .needsSetup: return "WriteBetter, needs setup"
        }
    }
}

/// The status-bar label. A pulsing dot marks "working" (M20); a `warning` dot marks
/// "needs setup". Under Reduce Motion the working dot is static at full opacity.
struct MenuBarIconView: View {
    let state: MenuBarIconFactory.State

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Image(nsImage: MenuBarIconFactory.markImage())
            .renderingMode(.template)
            .overlay(alignment: .topTrailing) { dot }
            .accessibilityLabel(MenuBarIconFactory.accessibilityLabel(for: state))
    }

    @ViewBuilder
    private var dot: some View {
        switch state {
        case .ready:
            EmptyView()
        case .working:
            Circle()
                .frame(width: 3, height: 3)
                .opacity(reduceMotion ? 1.0 : (pulse ? 1.0 : 0.30))
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }
        case .needsSetup:
            Circle()
                .fill(Theme.Color.warning)
                .frame(width: 3, height: 3)
        }
    }
}

// MARK: - Wordmark

/// "WriteBetter" — SF Pro Display Semibold, tracking −0.02 em, never coloured (§2.2).
struct Wordmark: View {
    var size: CGFloat = 22

    var body: some View {
        Text("WriteBetter")
            .font(.system(size: size, weight: .semibold))
            .tracking(-0.02 * size)
            .foregroundStyle(Theme.Color.textPrimary)
    }
}

// MARK: - Preview

#Preview("Brand mark") {
    VStack(spacing: Theme.Space.h1) {
        HStack(alignment: .center, spacing: Theme.Space.xl) {
            BrandMark(size: 18)
            BrandMark(size: 32)
            BrandMark(size: 64)
            BrandMark(size: 96)
        }

        HStack(spacing: Theme.Space.md) {
            BrandMark(size: 20)
            Wordmark(size: 22)
        }

        Divider()

        HStack(spacing: Theme.Space.h1) {
            ForEach(Array([MenuBarIconFactory.State.ready, .working, .needsSetup].enumerated()),
                    id: \.offset) { _, state in
                MenuBarIconView(state: state)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .frame(width: 22, height: 22)
            }
        }
    }
    .padding(Theme.Space.h2)
    .frame(width: 460, height: 380)
    .background(Theme.Color.bgBase)
}
