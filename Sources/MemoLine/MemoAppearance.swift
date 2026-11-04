import SwiftUI
import MemoCore

extension MemoColor {
    var title: String {
        switch self { case .butter: "奶油黄"; case .rose: "浅玫瑰"; case .sage: "鼠尾草绿"; case .sky: "雾蓝"; case .lavender: "薰衣草" }
    }
    func background(_ scheme: ColorScheme) -> Color {
        let rgb: (Double, Double, Double)
        switch self {
        case .butter: rgb = scheme == .dark ? (0.34,0.29,0.16) : (0.99,0.93,0.72)
        case .rose: rgb = scheme == .dark ? (0.37,0.23,0.26) : (0.98,0.83,0.83)
        case .sage: rgb = scheme == .dark ? (0.22,0.32,0.26) : (0.82,0.91,0.80)
        case .sky: rgb = scheme == .dark ? (0.20,0.29,0.37) : (0.81,0.90,0.96)
        case .lavender: rgb = scheme == .dark ? (0.30,0.25,0.39) : (0.89,0.84,0.96)
        }
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }
}

@MainActor
func confirmDelete(_ memo: Memo, store: MemoStore) {
    let previous = NSWorkspace.shared.frontmostApplication
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = "永久删除这张便签？"
    alert.informativeText = "删除后无法恢复。普通删除可以使用“撤销删除”找回。"
    alert.addButton(withTitle: "取消")
    alert.addButton(withTitle: "永久删除")
    if alert.runModal() == .alertSecondButtonReturn { store.delete(memo.id) }
    if previous?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previous?.activate() }
}

struct MemoActions: View {
    let memo: Memo
    @ObservedObject var store: MemoStore
    var edit: () -> Void
    var complete: (() -> Void)? = nil
    var discard: (() -> Void)? = nil
    var body: some View {
        Button("编辑", action: edit)
        if memo.status == .active {
            Menu(memo.reminderState == .none ? "设置提醒" : "修改提醒") {
                ReminderMenuItems(memo: memo, store: store)
            }
        }
        Menu("优先级") {
            ForEach(MemoPriority.allCases, id: \.self) { priority in
                Button { store.setPriority(memo.id, priority) } label: {
                    Label(priority.title, systemImage: memo.priority == priority ? "checkmark.circle.fill" : "circle")
                }
            }
        }
        Button(memo.isPinned ? "取消置顶" : "置顶") { store.togglePin(memo.id) }
        if memo.status != .archived {
            Button(memo.status == .completed ? "标记为未完成" : (memo.type == .todo ? "完成并移除" : "标记为完成")) {
                if let complete { complete() } else { store.toggleCompleted(memo.id) }
            }
        }
        Divider()
        Button("删除便签（可撤销）") {
            if let discard { discard() } else { store.discard(memo.id) }
        }
        Button("永久删除…", role: .destructive) { confirmDelete(memo, store: store) }
    }
}
