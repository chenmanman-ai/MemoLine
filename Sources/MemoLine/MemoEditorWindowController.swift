import AppKit
import SwiftUI
import MemoCore

private final class InlineEditorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// A regular key window; the nonactivating line never accepts text input.
@MainActor
final class MemoEditorWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    private let store: MemoStore
    private var draft: Memo
    private var isNew: Bool
    private let textView = NSTextView()
    private let typePicker = NSPopUpButton()
    private let priorityPicker = NSPopUpButton()
    private let inputHint = NSTextField(labelWithString: "")
    private let reminderPicker = NSPopUpButton()
    private let pinButton = NSButton()
    private let counter = NSTextField(labelWithString: "")
    private let feedback = NSTextField(wrappingLabelWithString: "")
    private var saveTimer: Timer?
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var forceClose = false
    private let inline: Bool
    private var choosingReminder = false
    var isCardEditor: Bool { inline }
    var onSaved: (() -> Void)?
    var onClosed: (() -> Void)?

    init(store: MemoStore, memo: Memo?, initialType: MemoType = .text, inlineFrame: NSRect? = nil) {
        self.store = store; self.draft = memo ?? Memo(type: initialType); self.isNew = memo == nil
        let cardScreen = LinePanel.screenUnderPointer()?.visibleFrame
        let newCardFrame = memo == nil ? NSRect(x: (cardScreen?.midX ?? 500) - 130,
            y: (cardScreen?.maxY ?? 700) - 370, width: 260, height: 330) : nil
        let cardFrame = inlineFrame ?? newCardFrame
        inline = cardFrame != nil
        let window: NSWindow
        if let cardFrame {
            window = InlineEditorPanel(contentRect: cardFrame, styleMask: [.borderless, .closable],
                                       backing: .buffered, defer: false)
            window.isOpaque = false; window.backgroundColor = .clear
            window.hasShadow = true
            window.appearance = NSAppearance(named: .aqua)
        } else {
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 400),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        }
        super.init(window: window)
        window.title = isNew ? "新建便签 · MemoLine" : "编辑便签 · MemoLine"
        window.isReleasedWhenClosed = false
        // The rope is floating; text input must be above it while editing.
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        window.delegate = self
        if inline { buildInlineContent(window); return }
        buildContent(window)
        let screen = LinePanel.screenUnderPointer()
        if let frame = screen?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: frame.midX - window.frame.width / 2,
                                          y: frame.maxY - window.frame.height - 36))
        } else { window.center() }
    }
    required init?(coder: NSCoder) { return nil }

    func present() {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = NSWorkspace.shared.frontmostApplication
        }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil); window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                if event.keyCode == 36 && event.modifierFlags.contains(.command) {
                    self.finish(); return nil
                }
                if event.keyCode == 53 {
                    if self.isNew {
                        self.forceClose = true; self.window?.close(); return nil
                    }
                    if self.inline { self.finish(); return nil }
                    if self.isNew { self.forceClose = true }
                    self.window?.performClose(nil); return nil
                }
                return event
            }
        }
    }
    private func buildInlineContent(_ window: NSWindow) {
        let root = NSView(); window.contentView = root
        let paper = NSHostingView(rootView: PaperSurface(seed: Int(draft.id.uuid.0)))
        paper.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(paper)
        NSLayoutConstraint.activate([
            paper.topAnchor.constraint(equalTo: root.topAnchor), paper.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            paper.leadingAnchor.constraint(equalTo: root.leadingAnchor), paper.trailingAnchor.constraint(equalTo: root.trailingAnchor)
        ])
        typePicker.addItems(withTitles: ["短文本", "待办"])
        typePicker.selectItem(at: draft.type == .todo ? 1 : 0)
        typePicker.target = self; typePicker.action = #selector(optionsChanged)
        typePicker.setAccessibilityLabel("便签类型")
        priorityPicker.addItems(withTitles: MemoPriority.allCases.map(\.title))
        priorityPicker.selectItem(at: draft.priority.rawValue - 1)
        priorityPicker.target = self; priorityPicker.action = #selector(optionsChanged)
        priorityPicker.setAccessibilityLabel("便签优先级")
        pinButton.setButtonType(.toggle)
        pinButton.bezelStyle = .texturedRounded
        pinButton.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "置顶")
        pinButton.imagePosition = .imageOnly
        pinButton.title = ""
        pinButton.state = draft.isPinned ? .on : .off
        pinButton.target = self; pinButton.action = #selector(pinChanged)
        pinButton.toolTip = "置顶便签"
        pinButton.setAccessibilityLabel("置顶便签")
        pinButton.identifier = NSUserInterfaceItemIdentifier("memoPin")
        let header = NSStackView(views: [priorityPicker, NSView(), typePicker, pinButton])
        header.spacing = 4
        configureReminderPicker()
        reminderPicker.target = self; reminderPicker.action = #selector(reminderChanged)
        reminderPicker.setAccessibilityLabel("设置或取消提醒")
        reminderPicker.font = .systemFont(ofSize: 11)
        inputHint.stringValue = draft.type == .todo ? "每行一项 · Return 换行" : "在这里写下想法…"
        inputHint.font = .systemFont(ofSize: 10); inputHint.textColor = .darkGray
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        textView.isRichText = false; textView.allowsUndo = true; textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 14); textView.textColor = NSColor(white: 0.16, alpha: 1)
        textView.insertionPointColor = .black
        textView.textContainerInset = NSSize(width: 0, height: 5)
        textView.frame = NSRect(x: 0, y: 0, width: 182, height: 120)
        textView.minSize = NSSize(width: 0, height: 120)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true; textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]; textView.textContainer?.widthTracksTextView = true
        textView.string = draft.text; textView.delegate = self
        textView.setAccessibilityLabel("卡片内编辑正文，最多 500 字；待办每行一项")
        scroll.documentView = textView
        counter.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        feedback.font = .systemFont(ofSize: 10); feedback.textColor = .darkGray
        feedback.stringValue = isNew ? "⌘↩ 挂上便签 · Esc 取消" : "⌘↩ 或 Esc 结束编辑"
        let done = NSButton(title: isNew ? "挂上便签" : "完成", target: self, action: #selector(finish))
        done.bezelStyle = .rounded
        let cancel = NSButton(title: isNew ? "取消" : "关闭", target: self, action: #selector(closeEditor))
        cancel.bezelStyle = .rounded
        let footer = NSStackView(views: [counter, NSView(), cancel, done])
        footer.spacing = 4
        for view in [header, reminderPicker, inputHint, scroll, feedback, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            reminderPicker.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            reminderPicker.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            reminderPicker.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            inputHint.topAnchor.constraint(equalTo: reminderPicker.bottomAnchor, constant: 5),
            inputHint.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            scroll.topAnchor.constraint(equalTo: inputHint.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: header.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: feedback.topAnchor, constant: -4),
            feedback.leadingAnchor.constraint(equalTo: header.leadingAnchor), feedback.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            feedback.heightAnchor.constraint(equalToConstant: 28),
            feedback.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -4),
            footer.leadingAnchor.constraint(equalTo: header.leadingAnchor), footer.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10)
        ])
        updateCounter()
    }
    private func buildContent(_ window: NSWindow) {
        let root = NSView(); window.contentView = root
        typePicker.addItems(withTitles: ["短文本", "待办"])
        typePicker.selectItem(at: draft.type == .todo ? 1 : 0)
        typePicker.target = self; typePicker.action = #selector(optionsChanged)
        typePicker.setAccessibilityLabel("便签类型")
        priorityPicker.addItems(withTitles: MemoPriority.allCases.map(\.title))
        priorityPicker.selectItem(at: draft.priority.rawValue - 1)
        priorityPicker.target = self; priorityPicker.action = #selector(optionsChanged)
        priorityPicker.setAccessibilityLabel("便签优先级")
        configureReminderPicker()
        reminderPicker.target = self; reminderPicker.action = #selector(reminderChanged)
        reminderPicker.setAccessibilityLabel("设置提醒")
        let top = NSStackView(views: [typePicker, priorityPicker, reminderPicker]); top.spacing = 12
        inputHint.font = .systemFont(ofSize: 11)
        inputHint.textColor = .secondaryLabelColor
        updateInputHint()
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        textView.isRichText = false; textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 15); textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 10, height: 12)
        textView.frame = NSRect(x: 0, y: 0, width: 384, height: 220)
        textView.minSize = NSSize(width: 0, height: 220)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true; textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = draft.text; textView.delegate = self
        textView.setAccessibilityLabel("便签正文，最多 500 个字符")
        scroll.documentView = textView
        counter.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        feedback.font = .systemFont(ofSize: 11); feedback.textColor = .secondaryLabelColor
        let save = NSButton(title: isNew ? "挂到绳子上  ⌘↩" : "完成  ⌘↩", target: self, action: #selector(finish))
        save.bezelStyle = .rounded
        let cancel = NSButton(title: isNew ? "取消" : "关闭", target: self, action: #selector(closeEditor))
        let bottom = NSStackView(views: [counter, NSView(), cancel, save]); bottom.spacing = 8
        for view in [top, inputHint, scroll, feedback, bottom] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: root.topAnchor, constant: 16), top.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            inputHint.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 10),
            inputHint.leadingAnchor.constraint(equalTo: top.leadingAnchor),
            scroll.topAnchor.constraint(equalTo: inputHint.bottomAnchor, constant: 8), scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            scroll.bottomAnchor.constraint(equalTo: feedback.topAnchor, constant: -10),
            feedback.leadingAnchor.constraint(equalTo: scroll.leadingAnchor), feedback.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            feedback.heightAnchor.constraint(equalToConstant: 42), feedback.bottomAnchor.constraint(equalTo: bottom.topAnchor, constant: -8),
            bottom.leadingAnchor.constraint(equalTo: scroll.leadingAnchor), bottom.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            bottom.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        ])
        updateCounter()
        feedback.stringValue = isNew ? "⌘ Return 保存 · Escape 取消" : "修改后自动保存 · Escape 关闭"
    }
    func textDidChange(_ notification: Notification) { changed() }
    @objc private func optionsChanged() { updateInputHint(); changed() }
    @objc private func pinChanged() {
        if isNew { draft.isPinned = pinButton.state == .on }
        else if !store.togglePin(draft.id) {
            pinButton.state = store.memo(draft.id)?.isPinned == true ? .on : .off
            feedback.stringValue = store.errorMessage ?? "置顶未保存，请重试。"
            feedback.textColor = .systemRed
        }
    }
    private func updateInputHint() {
        if inline {
            inputHint.stringValue = typePicker.indexOfSelectedItem == 1
                ? "每行一项 · Return 换行" : "直接输入 · 自动保存"
            return
        }
        inputHint.stringValue = typePicker.indexOfSelectedItem == 1
            ? "每行一个待办，按 Return 添加下一项；保存后可逐项勾选。"
            : "记录想法或小事；可切换为待办清单。"
    }
    @objc private func reminderChanged() {
        choosingReminder = true
        defer { choosingReminder = false }
        let current = (isNew ? draft : store.memo(draft.id)) ?? draft
        switch reminderPicker.indexOfSelectedItem {
        case 1: applyReminder(ReminderDates.todayLater())
        case 2: applyReminder(ReminderDates.tomorrow())
        case 3:
            if let date = ReminderPrompt.chooseDate(current: current.effectiveReminderDate) {
                applyReminder(date)
            }
        case 4: applyReminder(nil)
        default: break
        }
        configureReminderPicker()
    }
    private func configureReminderPicker() {
        let memo = (isNew ? draft : store.memo(draft.id)) ?? draft
        reminderPicker.removeAllItems()
        reminderPicker.addItem(withTitle: ReminderDates.label(for: memo).map { "提醒：\($0)" } ?? "设置提醒")
        reminderPicker.addItems(withTitles: ["今天稍后", "明天 09:00", "选择日期和时间…"])
        if memo.reminderState != .none { reminderPicker.addItem(withTitle: "取消提醒") }
        reminderPicker.selectItem(at: 0)
    }
    private func applyReminder(_ date: Date?) {
        if isNew {
            draft.reminderDate = date
            draft.reminderState = date == nil ? .none : .scheduled
            draft.snoozedUntil = nil
            draft.lastTriggeredAt = nil
        } else if let date {
            _ = store.setReminder(draft.id, date: date)
        } else {
            _ = store.cancelReminder(draft.id)
        }
        feedback.stringValue = date.map { "提醒已设为 \($0.formatted(date: .abbreviated, time: .shortened))" }
            ?? "提醒已取消"
        feedback.textColor = .secondaryLabelColor
    }
    private func changed() {
        updateCounter(); saveTimer?.invalidate()
        if !isNew && !textView.hasMarkedText() {
            feedback.stringValue = "正在保存…"
            saveTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.textView.hasMarkedText() else { return }
                    _ = self.persist()
                }
            }
        }
    }
    private func updateCounter() {
        counter.stringValue = "\(textView.string.count) / 500"
        counter.textColor = textView.string.count > 500 ? .systemRed : .secondaryLabelColor
    }
    @discardableResult private func persist() -> Bool {
        saveTimer?.invalidate()
        guard !textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              textView.string.count <= Memo.characterLimit else {
            feedback.stringValue = "尚未保存：请输入 1–500 个字符。"; feedback.textColor = .systemRed
            return false
        }
        draft.text = textView.string
        draft.type = typePicker.indexOfSelectedItem == 1 ? .todo : .text
        draft.priority = MemoPriority(rawValue: priorityPicker.indexOfSelectedItem + 1) ?? .p3
        let ok = isNew ? store.create(draft) : store.edit(draft.id, text: draft.text, type: draft.type,
                                                        color: draft.color, priority: draft.priority)
        if ok { isNew = false; feedback.stringValue = "已保存到此 Mac"; feedback.textColor = .secondaryLabelColor }
        else { feedback.stringValue = store.errorMessage ?? "保存失败，请重试。"; feedback.textColor = .systemRed }
        return ok
    }
    @objc private func finish() {
        guard persist() else { return }
        onSaved?(); forceClose = true
        if inline { window?.close() } else { window?.performClose(nil) }
    }
    func requestClose() { closeEditor() }
    @objc private func closeEditor() {
        guard let window else { return }
        if inline {
            if windowShouldClose(window) { window.close() }
        } else { window.performClose(nil) }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if forceClose { return true }
        if !isNew {
            if store.memo(draft.id) == nil {
                let alert = NSAlert(); alert.messageText = "此便签已在其他窗口删除"
                alert.informativeText = "编辑窗口中的文字尚未保存。可继续编辑并复制文字，或关闭此窗口。"
                alert.addButton(withTitle: "继续编辑"); alert.addButton(withTitle: "关闭窗口")
                return alert.runModal() == .alertSecondButtonReturn
            }
            return persist()
        }
        if textView.string.isEmpty { return true }
        let alert = NSAlert(); alert.messageText = "放弃未保存的新便签？"
        alert.addButton(withTitle: "继续编辑"); alert.addButton(withTitle: "放弃")
        return alert.runModal() == .alertSecondButtonReturn
    }
    func prepareToQuit() -> Bool {
        guard let window, window.isVisible else { return true }
        return windowShouldClose(window)
    }
    func windowDidResignKey(_ notification: Notification) {
        // Commit before dismissing. Invalid text and failed writes stay visible
        // so the user can recover or retry rather than lose their draft.
        if inline, !isNew, !choosingReminder, !forceClose, !textView.hasMarkedText(), persist() {
            forceClose = true; window?.close()
        }
    }
    func windowWillClose(_ notification: Notification) {
        forceClose = true
        saveTimer?.invalidate()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }; keyMonitor = nil
        if NSApp.isActive { previousApp?.activate() }
        onClosed?()
    }
}
