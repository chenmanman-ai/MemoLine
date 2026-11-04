#if DEBUG
import AppKit
import SwiftUI
import MemoCore

/// Renders the real card views against fixture data, without opening the user's
/// document, starting notifications or registering application shortcuts.
@MainActor enum DesignPreview {
    static func verifyNewCard() throws {
        let store = MemoStore(persistence: PreviewDisk())
        let editor = MemoEditorWindowController(store: store, memo: nil)
        editor.present()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard editor.isCardEditor, let text = editor.window?.firstResponder as? NSTextView,
              let root = editor.window?.contentView else {
            throw NSError(domain: "Preview", code: 1, userInfo: [NSLocalizedDescriptionKey: "New card focus failed"])
        }
        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap { descendants($0) }
        }
        let views = descendants(root)
        views.compactMap { $0 as? NSButton }.first(where: { $0.identifier?.rawValue == "memoPin" })?.performClick(nil)
        let pickers = views.compactMap { $0 as? NSPopUpButton }
        guard let type = pickers.first(where: { $0.itemTitles == ["短文本", "待办"] }),
              let priority = pickers.first(where: { $0.itemTitles.contains("P1 紧急") }),
              let reminder = pickers.first(where: { $0.itemTitles.contains("明天 09:00") }),
              let save = views.compactMap({ $0 as? NSButton }).first(where: { $0.title == "挂上便签" }) else {
            print("Picker titles: \(pickers.map(\.itemTitles))")
            throw NSError(domain: "Preview", code: 2, userInfo: [NSLocalizedDescriptionKey: "New card controls missing"])
        }
        for (picker, index) in [(type, 1), (priority, 0), (reminder, 2)] {
            picker.selectItem(at: index)
            if let action = picker.action { NSApp.sendAction(action, to: picker.target, from: picker) }
        }
        text.insertText("买牛奶\n寄快递", replacementRange: text.selectedRange())
        root.layoutSubtreeIfNeeded()
        if let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
            root.cacheDisplay(in: root.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) {
                try png.write(to: URL(fileURLWithPath: "build/new-card.png"), options: .atomic)
            }
        }
        save.performClick(nil)
        guard let memo = store.memos.first, memo.todoItems.count == 2, memo.priority == .p1,
              memo.type == .todo, memo.isPinned, memo.reminderState == .scheduled, editor.window?.isVisible == false else {
            print("Saved memos: \(store.memos.count), state: \(String(describing: store.memos.first)), visible: \(String(describing: editor.window?.isVisible))")
            throw NSError(domain: "Preview", code: 3, userInfo: [NSLocalizedDescriptionKey: "New card save verification failed"])
        }
        print("PASS new card: keyboard focus, type, priority, pin, reminder, checklist, save")
    }
    static func verifyInlineEditor() throws {
        let store = MemoStore(persistence: PreviewDisk())
        let memo = Memo(text: "编辑前", type: .todo)
        guard store.create(memo) else { throw CocoaError(.fileWriteUnknown) }
        let editor = MemoEditorWindowController(store: store, memo: memo,
            inlineFrame: NSRect(x: 200, y: 300, width: 210, height: 258))
        editor.present()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let text = editor.window?.firstResponder as? NSTextView else {
            throw NSError(domain: "MemoLine.InlineEditor", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "卡片未获得文字输入焦点"])
        }
        text.selectAll(nil)
        text.insertText("第一项\n第二项", replacementRange: text.selectedRange())
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        guard store.memo(memo.id)?.text == "第一项\n第二项",
              store.memo(memo.id)?.todoItems.count == 2 else {
            throw NSError(domain: "MemoLine.InlineEditor", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "卡片自动保存或待办拆分失败"])
        }
        guard editor.prepareToQuit() else { throw CocoaError(.fileWriteUnknown) }
        editor.window?.close()
        print("PASS inline editor: keyboard focus, text input, autosave, checklist, close")
    }
    private final class PreviewDisk: MemoPersistence {
        func load() throws -> Data? { nil }
        func write(_ data: Data) throws {}
    }
    static func render(to path: String, dark: Bool) throws {
        let store = MemoStore(persistence: PreviewDisk())
        let state = LineState(); state.revealed = true; state.previewOnly = true
        let discarded = Memo(text: "预览撤销按钮")
        store.create(discarded); store.discard(discarded.id)
        let contents = ["确认合同修改\n今天下班前发给客户", "整理产品截图\n准备演示要点\n检查会议设备", "预约牙齿检查\n问一下周六是否有空位", "买咖啡豆\n试试浅烘焙", "一个小想法\n把灵感先留在这里"]
        for index in (0..<5).reversed() {
            var memo = Memo(text: contents[index], type: index == 1 ? .todo : .text)
            memo.priority = MemoPriority(rawValue: index + 1) ?? .p3
            memo.isPinned = index == 0
            store.create(memo)
            if index == 0 { store.setReminder(memo.id, date: Date().addingTimeInterval(3600)) }
        }
        let view = MemoLineView(store: store, state: state, edit: { _ in }, create: {})
            .frame(width: 1280, height: 380)
            .padding(.top, 25)
            .background(LinearGradient(colors: dark
                ? [Color(red: 0.10, green: 0.16, blue: 0.25), Color(red: 0.23, green: 0.29, blue: 0.38)]
                : [Color(red: 0.72, green: 0.83, blue: 0.93), Color(red: 0.89, green: 0.90, blue: 0.92)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .environment(\.colorScheme, dark ? .dark : .light)
        // ImageRenderer omits AppKit-backed menus and scroll views. Capture a
        // hosted native view instead to validate the actual shipping controls.
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: 1280, height: 405),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
#endif
