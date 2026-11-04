import SwiftUI
import MemoCore

struct MemoDeparture: Identifiable {
    let memo: Memo
    let position: CGPoint
    let id = UUID()
}

/// A display-only snapshot. The corresponding delete and Undo entry are already
/// committed atomically before this view appears; animation never writes data.
struct FallingMemoView: View {
    let memo: Memo
    var finished: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var gone = false
    @State private var fallDistance: CGFloat = 0
    @State private var rotation = 0.0

    var body: some View {
        PaperSurface(seed: Int(memo.id.uuid.0))
            .overlay {
                VStack(alignment: .leading, spacing: 14) {
                    PriorityBadge(priority: memo.priority)
                    Text(memo.text).font(.system(size: 15)).lineLimit(7)
                        .foregroundStyle(Color(white: 0.16))
                    Spacer()
                }.padding(14).padding(.top, 5)
            }
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.3), lineWidth: 0.7))
            .shadow(color: .black.opacity(0.18), radius: 7, y: 5)
            .frame(width: LineLayout.cardWidth, height: 258)
        .frame(width: LineLayout.cardWidth, height: 278)
        .rotationEffect(.degrees(reduceMotion ? 0 : rotation))
        .offset(x: reduceMotion ? 0 : fallDistance * 0.10,
                y: reduceMotion ? 0 : fallDistance)
        .scaleEffect(reduceMotion ? 1 : (gone ? 0.92 : 1))
        .opacity(gone ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: reduceMotion) {
            if reduceMotion { finished(); return }
            // A short release, followed by an accelerating fall and turn.
            withAnimation(.easeIn(duration: 0.62)) {
                fallDistance = 245
                rotation = Double.random(in: -34 ... 34)
            }
            do { try await Task.sleep(for: .milliseconds(380)) } catch { return }
            withAnimation(.easeIn(duration: 0.24)) { gone = true }
            do { try await Task.sleep(for: .milliseconds(260)) } catch { return }
            finished()
        }
    }
}
