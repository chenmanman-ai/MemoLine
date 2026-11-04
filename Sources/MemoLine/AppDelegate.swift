import AppKit
import SwiftUI
import Carbon
import Combine
import MemoCore

final class PassiveHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = MemoStore(persistence: FileMemoPersistence(url: MemoStore.defaultURL))
    private let line = LineState()
    private let fullScreenPolicy = FullScreenPolicy()
    private lazy var reminderController = ReminderController(store: store)
    private var panel: LinePanel?
    private var statusItem: NSStatusItem?
    private var editor: MemoEditorWindowController?
    private var newHotKey: HotKey?
    private var lineHotKey: HotKey?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var hoverSince: Date?
    private var awaySince: Date?
    private var peekUntil = Date.distantPast
    private var manuallyHidden = false
    private var manuallyShown = false
    private var menuOpen = false
    private var suppressHover = false
    private var lastScreen: NSScreen?
    private var notifications: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        if !store.restoreAllArchived() {
            notify("无法恢复旧归档便签", store.errorMessage ?? "数据已保留，请检查存储位置后重试。")
        }
        let host = PassiveHostingView(rootView: MemoLineView(store: store, state: line,
            edit: { [weak self] in self?.openInlineEditor($0) },
            create: { [weak self] in self?.openEditor(nil) }))
        host.sizingOptions = []
        let panel = LinePanel(content: host)
        self.panel = panel
        panel.placeOnScreen()
        configureFullScreen()
        panel.onScroll = { [weak self] event in
            guard let self, let panel = self.panel else { return false }
            let point = CGPoint(x: event.locationInWindow.x, y: panel.frame.height - event.locationInWindow.y)
            if abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX),
               self.store.ropeMemos.contains(where: {
                   $0.type == .todo && self.line.hitRects[$0.id]?.contains(point) == true
               }) { return false }
            let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
            self.scroll(by: -delta * (event.hasPreciseScrollingDeltas ? 1 : 10))
            return true
        }
        // A square item is much less likely to be hidden by a crowded menu bar.
        // The tooltip and accessibility label still expose the product name.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        item.button?.image = Brand.statusIcon()
        item.button?.title = ""
        item.button?.imagePosition = .imageOnly
        item.button?.setAccessibilityLabel("MemoLine 便签菜单")
        item.isVisible = true
        item.button?.toolTip = "MemoLine · 留住小事"
        let menu = NSMenu(); menu.delegate = self; menu.autoenablesItems = false
        item.menu = menu
        reminderController.onFocusMemo = { [weak self] id in self?.focusReminder(id) }
        reminderController.onRingingChanged = { [weak self] ids in
            self?.statusItem?.button?.image = Brand.statusIcon(hasRingingReminder: !ids.isEmpty)
            self?.statusItem?.button?.toolTip = ids.isEmpty
                ? "MemoLine · 留住小事" : "MemoLine · 有 \(ids.count) 个提醒正在响铃"
        }
        reminderController.onPermissionLimited = { [weak self] message in
            self?.notify("系统通知未开启", message)
        }
        reminderController.start()
        newHotKey = HotKey(Shortcut(keyCode: kVK_ANSI_N, modifiers: [.control, .option], key: "n"), id: 1) { [weak self] in self?.openEditor(nil) }
        registerLineShortcut()
        if newHotKey == nil { notify("新建便签快捷键注册失败", "⌃⌥N 可能已被其他应用使用。你仍可通过菜单栏新建便签。") }
        store.$errorMessage.removeDuplicates().receive(on: RunLoop.main).sink { [weak self] message in
            guard let self else { return }
            self.statusItem?.button?.toolTip = message == nil ? "MemoLine · 留住小事" : "MemoLine · 保存或恢复需要处理"
            if let message, self.editor == nil { self.notify("便签数据需要处理", message) }
        }.store(in: &cancellables)
        // Pointer tracking does not need display-refresh frequency. Ten checks per
        // second still feels immediate while cutting idle wakeups by two thirds.
        // Default run-loop mode pauses this timer while a context menu tracks.
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        notifications.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.panel?.placeOnScreen(); self?.lastScreen = LinePanel.screenUnderPointer()
                    self?.fullScreenPolicy.invalidate(); self?.scroll(by: 0)
                }
            })
        notifications.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.fullScreenPolicy.invalidate(); self?.tick() }
            })
        if Preferences.alwaysVisible {
            reveal()
        } else if !UserDefaults.standard.bool(forKey: "didShowFirstLaunchRope") {
            // A first launch should visibly succeed without bringing back a
            // separate welcome window. Keep the rope around long enough for
            // the user to discover the New Memo button.
            UserDefaults.standard.set(true, forKey: "didShowFirstLaunchRope")
            peekUntil = Date().addingTimeInterval(8)
            reveal()
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        manuallyHidden = false
        peekUntil = Date().addingTimeInterval(3)
        reveal()
        return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        editor?.prepareToQuit() == false ? .terminateCancel : .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        reminderController.stop()
    }

    private func openInlineEditor(_ memo: Memo) {
        guard let panel, let rect = line.hitRects[memo.id] else { openEditor(memo); return }
        let frame = NSRect(x: panel.frame.minX + rect.midX - LineLayout.cardWidth / 2,
                           y: panel.frame.maxY - rect.midY - 129,
                           width: LineLayout.cardWidth, height: 258)
        openEditor(memo, inlineFrame: frame)
    }

    private func openEditor(_ memo: Memo?, newType: MemoType = .text, inlineFrame: NSRect? = nil) {
        if let editor, editor.window?.isVisible == true {
            editor.requestClose()
            if editor.window?.isVisible == true { return }
        }
        let controller = MemoEditorWindowController(store: store, memo: memo, initialType: newType, inlineFrame: inlineFrame)
        line.editingCard = controller.isCardEditor
        line.editingID = inlineFrame == nil ? nil : memo?.id
        controller.onClosed = { [weak self] in
            self?.editor = nil; self?.line.editingID = nil; self?.line.editingCard = false
        }
        controller.onSaved = { [weak self] in
            guard let self else { return }
            self.manuallyHidden = false; self.peekUntil = Date().addingTimeInterval(3)
            self.reveal()
            if let latest = self.store.ropeMemos.max(by: { $0.updatedAt < $1.updatedAt }),
               let index = self.store.ropeMemos.firstIndex(where: { $0.id == latest.id }), let panel = self.panel {
                let spacing = LineLayout.spacing(for: self.line.cardSize)
                self.line.scroll = max(0, CGFloat(index) * spacing - panel.frame.width / 2 + spacing)
                self.scroll(by: 0)
            }
        }
        editor = controller; controller.present()
    }
    private func focusReminder(_ id: UUID) {
        guard let memo = store.memo(id), memo.status == .active, let panel else { return }
        panel.placeOnScreen()
        lastScreen = LinePanel.screenUnderPointer()
        panel.orderFrontRegardless()
        line.revealed = true
        line.selected = id
        if let index = store.ropeMemos.firstIndex(where: { $0.id == id }) {
            let spacing = LineLayout.spacing(for: line.cardSize)
            line.scroll = max(0, CGFloat(index) * spacing
                - panel.frame.width / 2 + spacing)
            scroll(by: 0)
        }
        peekUntil = Date().addingTimeInterval(5)
    }
    private func configureFullScreen() {
        panel?.collectionBehavior = Preferences.showOverFullScreen
            ? [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            : [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
    }
    private func reveal() {
        guard let panel, let screen = LinePanel.screenUnderPointer(), !fullScreenPolicy.blocks(screen) else { return }
        panel.placeOnScreen(screen); lastScreen = LinePanel.screenUnderPointer()
        panel.orderFrontRegardless()
        line.revealed = true
    }
    private func hide() {
        line.revealed = false; panel?.ignoresMouseEvents = true
        let delay = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.0 : 0.45
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.line.revealed else { return }; self.panel?.orderOut(nil)
        }
    }
    private func toggleLine() {
        if line.revealed { manuallyHidden = true; manuallyShown = false; suppressHover = true; hide() }
        else {
            manuallyHidden = false; manuallyShown = true
            hoverSince = nil; awaySince = nil
            reveal()
        }
    }
    private func scroll(by delta: CGFloat) {
        guard let panel else { return }
        let limit = max(0, CGFloat(store.ropeMemos.count) * LineLayout.spacing(for: line.cardSize) + 20 - panel.frame.width)
        line.scroll = min(limit, max(0, line.scroll + delta))
    }
    private func tick() {
        guard let panel, let screen = LinePanel.screenUnderPointer(), !menuOpen, !line.showingMenu,
              !line.editingCard else { return }
        if fullScreenPolicy.blocks(screen) {
            if line.revealed { hide() }
            return
        }
        let mouse = NSEvent.mouseLocation, now = Date()
        let band = max(NSStatusBar.system.thickness, screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top)
        let atTop = mouse.y >= screen.frame.maxY - band
        if !atTop { suppressHover = false; hoverSince = nil }
        if line.revealed, lastScreen != screen {
            panel.placeOnScreen(screen); lastScreen = screen; scroll(by: 0)
        }
        if Preferences.alwaysVisible && !manuallyHidden {
            if !line.revealed { reveal() }
        } else if !line.revealed && !manuallyHidden && atTop && !suppressHover && !Preferences.alwaysVisible {
            if hoverSince == nil { hoverSince = now }
            if let hoverSince, now.timeIntervalSince(hoverSince) > 0.3 { reveal() }
        }
        if line.revealed {
            let local = panel.convertPoint(fromScreen: mouse)
            let flipped = CGPoint(x: local.x, y: panel.frame.height - local.y)
            if !line.dragging {
                let overCard = line.hitRects.values.contains { $0.insetBy(dx: -6, dy: -6).contains(flipped) }
                panel.ignoresMouseEvents = !overCard
            }
            var zone = panel.frame; zone.size.height = screen.frame.maxY - zone.minY
            let inside = zone.contains(mouse)
            if inside { manuallyShown = false }
            if inside || manuallyShown || line.dragging || !line.departures.isEmpty || now < peekUntil || Preferences.alwaysVisible {
                awaySince = nil
            } else {
                if awaySince == nil { awaySince = now }
                if let awaySince, now.timeIntervalSince(awaySince) > 0.6 { hide(); self.awaySince = nil }
            }
            scroll(by: 0)
        }
    }
    private func registerLineShortcut() {
        lineHotKey = nil
        if let shortcut = Shortcut.current {
            lineHotKey = HotKey(shortcut, id: 2) { [weak self] in self?.toggleLine() }
            if lineHotKey == nil { notify("绳子快捷键不可用", "该组合键可能已被占用，请在菜单栏更换。") }
        }
    }
    private func changeShortcut() {
        lineHotKey = nil
        ShortcutRecorder.shared.record { [weak self] result in
            guard let self else { return }
            let previous = Shortcut.current
            if let result { Shortcut.current = result }
            self.registerLineShortcut()
            if Shortcut.current != nil && self.lineHotKey == nil { Shortcut.current = previous; self.registerLineShortcut() }
        }
    }
    func menuWillOpen(_ menu: NSMenu) { menuOpen = true; suppressHover = true }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let newMemo = ActionMenuItem("新建便签", key: "n") { [weak self] in self?.openEditor(nil) }
        newMemo.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(newMemo)
        menu.addItem(ActionMenuItem("新建待办便签") { [weak self] in self?.openEditor(nil, newType: .todo) })
        menu.addItem(.separator())
        let toggle = ActionMenuItem(line.revealed ? "隐藏便签绳" : "显示便签绳") { [weak self] in self?.toggleLine() }
        if let shortcut = Shortcut.current {
            toggle.keyEquivalent = shortcut.key; toggle.keyEquivalentModifierMask = shortcut.modifiers
        }
        menu.addItem(toggle)
        let display = NSMenuItem(title: "显示方式", action: nil, keyEquivalent: "")
        let modes = NSMenu(); modes.autoenablesItems = false
        for (title, persistent) in [("自动收起", false), ("常驻显示", true)] {
            let option = ActionMenuItem(title) { [weak self] in
                Preferences.alwaysVisible = persistent; self?.manuallyHidden = false
                if persistent { self?.reveal() } else { self?.hide() }
            }
            option.state = Preferences.alwaysVisible == persistent ? .on : .off
            modes.addItem(option)
        }
        modes.addItem(.separator())
        let full = ActionMenuItem("允许覆盖全屏应用") { [weak self] in
            Preferences.showOverFullScreen.toggle(); self?.configureFullScreen(); self?.hide()
        }
        full.state = Preferences.showOverFullScreen ? .on : .off; modes.addItem(full)
        let sound = ActionMenuItem("删除音效") {
            Preferences.deletionSoundEnabled.toggle()
        }
        sound.state = Preferences.deletionSoundEnabled ? .on : .off
        modes.addItem(sound)
        display.submenu = modes; menu.addItem(display)
        let sizeItem = NSMenuItem(title: "大小", action: nil, keyEquivalent: "")
        let sizes = NSMenu(); sizes.autoenablesItems = false
        for size in MemoCardSize.allCases {
            let option = ActionMenuItem(size.title) { [weak self] in
                guard let self else { return }
                Preferences.cardSize = size
                self.line.cardSize = size
                self.scroll(by: 0)
            }
            option.state = line.cardSize == size ? .on : .off
            sizes.addItem(option)
        }
        sizeItem.submenu = sizes; menu.addItem(sizeItem)
        let shortcutItem = NSMenuItem(title: "快捷键", action: nil, keyEquivalent: "")
        let shortcuts = NSMenu(); shortcuts.autoenablesItems = false
        let newHint = NSMenuItem(title: "新建便签：⌃⌥N", action: nil, keyEquivalent: "")
        newHint.isEnabled = false; shortcuts.addItem(newHint)
        shortcuts.addItem(ActionMenuItem("显示 / 隐藏：\(Shortcut.current?.display ?? "未设置")…") { [weak self] in self?.changeShortcut() })
        shortcutItem.submenu = shortcuts; menu.addItem(shortcutItem)
        menu.addItem(.separator())
        let undo = ActionMenuItem("撤销删除便签") { [weak self] in
            guard let self, self.store.undoDeletion() else { return }
            self.peekUntil = Date().addingTimeInterval(3); self.manuallyHidden = false; self.reveal()
        }
        undo.isEnabled = store.canUndoDeletion; menu.addItem(undo)
        if store.errorMessage != nil {
            menu.addItem(ActionMenuItem("查看数据错误…") { [weak self] in
                guard let self, let message = self.store.errorMessage else { return }
                self.notify("便签数据需要处理", message)
            })
        }
        menu.addItem(ActionMenuItem("关于 MemoLine…") { [weak self] in self?.showAbout() })
        menu.addItem(.separator())
        let quit = ActionMenuItem("退出 MemoLine", key: "q") { NSApp.terminate(nil) }
        quit.keyEquivalentModifierMask = [.command]
        menu.addItem(quit)
    }
    private func showAbout() {
        let alert = NSAlert(); alert.messageText = "MemoLine 1.10"
        alert.informativeText = "留住小事，腾出心思。\n原生、本地、私密的短便签。\n\n基于 Alejandro Buján 的 Tendedero 开源代码改造（MIT）。\nMemoLine 为独立衍生项目，未经原作者背书。\n原项目名称、图标及文档图片未用于本应用。"
        alert.addButton(withTitle: "好"); alert.addButton(withTitle: "查看许可证")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn,
           let url = Bundle.main.url(forResource: "LICENSE", withExtension: "txt") { NSWorkspace.shared.open(url) }
    }
    private func notify(_ title: String, _ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
            NSApp.activate(ignoringOtherApps: true); alert.runModal()
        }
    }
    private func installMainMenu() {
        let main = NSMenu()
        let app = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(ActionMenuItem("新建便签") { [weak self] in self?.openEditor(nil) })
        appMenu.addItem(ActionMenuItem("新建待办便签") { [weak self] in self?.openEditor(nil, newType: .todo) })
        appMenu.addItem(.separator())
        appMenu.addItem(ActionMenuItem("显示 / 隐藏便签绳") { [weak self] in self?.toggleLine() })
        let undo = ActionMenuItem("撤销删除便签") { [weak self] in _ = self?.store.undoDeletion() }
        undo.isEnabled = store.canUndoDeletion
        appMenu.addItem(undo)
        let sound = ActionMenuItem("删除音效") { Preferences.deletionSoundEnabled.toggle() }
        sound.state = Preferences.deletionSoundEnabled ? .on : .off
        appMenu.addItem(sound)
        appMenu.addItem(.separator())
        appMenu.addItem(ActionMenuItem("关于 MemoLine") { [weak self] in self?.showAbout() })
        appMenu.addItem(ActionMenuItem("退出 MemoLine", key: "q") { NSApp.terminate(nil) })
        app.submenu = appMenu; main.addItem(app)
        let editItem = NSMenuItem(); let editMenu = NSMenu(title: "编辑")
        for (name, action, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            editMenu.addItem(withTitle: name, action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = editMenu; main.addItem(editItem); NSApp.mainMenu = main
    }
}

final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key); target = self
    }
    required init(coder: NSCoder) { handler = {}; super.init(coder: coder) }
    @objc private func fire() { handler() }
}
