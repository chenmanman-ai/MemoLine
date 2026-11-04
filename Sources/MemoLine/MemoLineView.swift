import SwiftUI
import MemoCore

enum LineLayout {
    static let panelHeight: CGFloat = 346
    static let cardWidth: CGFloat = 210
    static let spacing: CGFloat = 242
    static func spacing(for size: MemoCardSize) -> CGFloat { spacing * size.scale }
    static let ropeTop: CGFloat = 10
    static func sag(width: CGFloat) -> CGFloat { min(25, width * 0.018) }
    static func ropeY(x: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return ropeTop }
        let f = min(1, max(0, x / width))
        return ropeTop + 4 * sag(width: width) * f * (1 - f)
    }
    static func x(index: Int, count: Int, width: CGFloat, scroll: CGFloat, size: MemoCardSize) -> CGFloat {
        let itemSpacing = spacing(for: size)
        let total = CGFloat(count) * itemSpacing
        let start = total < width ? (width - total) / 2 : 10
        return start + itemSpacing * (CGFloat(index) + 0.5) - scroll
    }
}

final class LineState: ObservableObject {
    var previewOnly = false
    var editingCard = false
    @Published var revealed = false
    @Published var scroll: CGFloat = 0
    @Published var selected: UUID?
    @Published var editingID: UUID?
    @Published var departures: [MemoDeparture] = []
    @Published var cardSize = Preferences.cardSize
    let createButtonID = UUID()
    let undoButtonID = UUID()
    var hitRects: [UUID: CGRect] = [:]
    var dragging = false
    var showingMenu = false
}

struct MemoLineView: View {
    @ObservedObject var store: MemoStore
    @ObservedObject var state: LineState
    var edit: (Memo) -> Void
    var create: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geo in
            let items = store.ropeMemos
            // Build only cards intersecting the panel (plus one-card padding).
            // The full collection remains in MemoStore and participates in order.
            let visibleItems = Array(items.enumerated()).filter { entry in
                let x = LineLayout.x(index: entry.offset, count: items.count,
                                     width: geo.size.width, scroll: state.scroll, size: state.cardSize)
                let displayWidth = LineLayout.cardWidth * state.cardSize.scale
                return x >= -displayWidth && x <= geo.size.width + displayWidth
            }
            ZStack(alignment: .topLeading) {
                Rope(width: geo.size.width)
                if state.revealed || state.previewOnly {
                ForEach(visibleItems, id: \.element.id) { index, memo in
                    let x = LineLayout.x(index: index, count: items.count, width: geo.size.width,
                                         scroll: state.scroll, size: state.cardSize)
                    HangingMemoView(memo: memo, store: store, state: state, edit: { edit(memo) }, reorder: { delta in
                        let steps = Int((delta / LineLayout.spacing(for: state.cardSize)).rounded())
                        let destination = min(items.count - 1, max(0, index + steps))
                        if destination != index { store.move(memo.id, before: items[destination].id, after: destination > index) }
                    }, complete: {
                        if memo.type == .todo && memo.status == .active {
                            remove(memo, at: CGPoint(x: x, y: LineLayout.ropeY(x: x, width: geo.size.width) + 128))
                        } else { store.toggleCompleted(memo.id) }
                    }, discard: {
                        remove(memo, at: CGPoint(x: x, y: LineLayout.ropeY(x: x, width: geo.size.width) + 128))
                    })
                    .scaleEffect(state.cardSize.scale, anchor: .top)
                    .position(x: x, y: LineLayout.ropeY(x: x, width: geo.size.width) + 128)
                }
                }
                ForEach(state.departures) { departure in
                    FallingMemoView(memo: departure.memo) {
                        state.departures.removeAll { $0.id == departure.id }
                    }
                    .position(departure.position)
                    .zIndex(5)
                }
                if store.canUndoDeletion {
                    Button { store.undoDeletion() } label: {
                        Label("撤销删除", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .background(.regularMaterial, in: Capsule())
                    .disabled(!state.departures.isEmpty)
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: HitRectsKey.self,
                            value: [state.undoButtonID: geo.frame(in: .named("line"))])
                    })
                    .position(x: 80, y: 18)
                    .zIndex(10)
                }
                Button(action: create) {
                    Label(items.isEmpty ? "新建第一张便签" : "新建便签", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
                .help("新建便签，也可按 Control + Option + N")
                .accessibilityLabel("新建便签")
                .background(GeometryReader { geo in
                    Color.clear.preference(key: HitRectsKey.self,
                        value: [state.createButtonID: geo.frame(in: .named("line"))])
                })
                .position(x: max(80, geo.size.width - 85), y: 18)
                .zIndex(10)
            }
            .coordinateSpace(name: "line")
            .offset(y: state.revealed ? 0 : -LineLayout.panelHeight - 12)
            .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86), value: state.revealed)
            .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: items.map(\.id))
        }
        .onPreferenceChange(HitRectsKey.self) { state.hitRects = $0 }
        .onChange(of: state.revealed) { _, revealed in
            if !revealed { state.hitRects.removeAll(keepingCapacity: true) }
        }
    }
    private func remove(_ memo: Memo, at position: CGPoint) {
        guard store.discard(memo.id) else { return }
        DeletionSound.play()
        if !reduceMotion {
            state.departures.append(MemoDeparture(memo: memo, position: position))
        }
        if state.selected == memo.id { state.selected = nil }
    }

}
