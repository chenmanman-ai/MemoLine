import AppKit
import SwiftUI
import MemoCore

@MainActor
private enum SharedPaperTexture {
    /// A single decoded texture shared by every card and editor. The previous
    /// implementation rebuilt 1,800 fibers in every PaperSurface Canvas.
    static let image: NSImage = {
        let size = NSSize(width: 256, height: 256)
        let image = NSImage(size: size)
        image.lockFocus()
        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus(); return image
        }
        context.setLineWidth(0.45)
        for index in 0..<1800 {
            let hash = (index * 7919 + 37 * 131) % 104729
            let x = CGFloat(hash % 997) / 997 * size.width
            let y = CGFloat((hash * 37) % 991) / 991 * size.height
            let light = index.isMultiple(of: 3)
            context.setStrokeColor((light
                ? NSColor.white.withAlphaComponent(0.28)
                : NSColor.brown.withAlphaComponent(0.055)).cgColor)
            context.move(to: CGPoint(x: x, y: y))
            context.addLine(to: CGPoint(x: x + CGFloat(hash % 4 + 1) * 0.45, y: y + 0.5))
            context.strokePath()
        }
        image.unlockFocus()
        return image
    }()
}

extension MemoPriority {
    var title: String {
        switch self {
        case .p1: "P1 紧急"
        case .p2: "P2 高"
        case .p3: "P3 中"
        case .p4: "P4 低"
        case .p5: "P5 随手记"
        }
    }
    var blue: Color {
        switch self {
        case .p1: Color(red: 0.08, green: 0.28, blue: 0.55)
        case .p2: Color(red: 0.18, green: 0.43, blue: 0.76)
        case .p3: Color(red: 0.65, green: 0.81, blue: 0.96)
        case .p4: Color(red: 0.82, green: 0.89, blue: 0.97)
        case .p5: Color(red: 0.91, green: 0.94, blue: 0.98)
        }
    }
    var ink: Color { rawValue <= 2 ? .white : Color(red: 0.10, green: 0.23, blue: 0.39) }
}

struct PriorityBadge: View {
    let priority: MemoPriority
    var body: some View {
        Text(priority.title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(priority.ink)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(priority.blue, in: RoundedRectangle(cornerRadius: 7))
            .accessibilityLabel("优先级 \(priority.title)")
    }
}

/// Opaque paper with deterministic fibers and shallow folds; never uses a timer
/// or randomness during rendering, so the texture cannot shimmer while reading.
struct PaperSurface: View {
    var seed: Int = 0
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            Color(red: scheme == .dark ? 0.96 : 1, green: scheme == .dark ? 0.94 : 0.987,
                  blue: scheme == .dark ? 0.89 : 0.957)
            Image(nsImage: SharedPaperTexture.image)
                .resizable(resizingMode: .tile)
                .opacity(scheme == .dark ? 0.82 : 1)
            Canvas { context, size in
                // Broad, faint shadow/highlight pairs suggest soft paper creases.
                for index in 0..<3 {
                    let variation = Double((seed + index * 17) % 23) / 230
                    let y = size.height * (0.14 + Double(index) * 0.31 + variation)
                    var fold = Path()
                    fold.move(to: CGPoint(x: -10, y: y))
                    fold.addQuadCurve(to: CGPoint(x: size.width + 10, y: y + (index == 1 ? -24 : 27)),
                                      control: CGPoint(x: size.width * 0.48, y: y - 11))
                    context.stroke(fold, with: .color(.brown.opacity(0.025)), lineWidth: 7)
                    context.stroke(fold, with: .color(.brown.opacity(0.045)), lineWidth: 1)
                    var highlight = context
                    highlight.translateBy(x: 0, y: 1.7)
                    highlight.stroke(fold, with: .color(.white.opacity(0.55)), lineWidth: 1.3)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
