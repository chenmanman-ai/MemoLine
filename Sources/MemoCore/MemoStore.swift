import Foundation
import Combine
import os

public protocol MemoPersistence {
    func load() throws -> Data?
    func write(_ data: Data) throws
}

public struct FileMemoPersistence: MemoPersistence {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }
    public func write(_ data: Data) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        // Retain the previous complete snapshot before replacing the current one.
        if fm.fileExists(atPath: url.path) {
            try Data(contentsOf: url).write(to: url.appendingPathExtension("backup"), options: .atomic)
        }
        try data.write(to: url, options: .atomic)
    }
}

public enum MemoStoreError: LocalizedError {
    case invalidText, duplicateID, unsupportedVersion, recoveryRequired, missingMemo
    public var errorDescription: String? {
        switch self {
        case .invalidText: return "便签需要包含文字，且不能超过 500 个字符。"
        case .duplicateID: return "数据中出现重复的便签编号。"
        case .unsupportedVersion: return "此数据由更新版本创建，请使用更新版本打开。"
        case .recoveryRequired: return "读取失败，已停止写入以保护原文件。请先恢复数据并重新启动。"
        case .missingMemo: return "这张便签已不存在，请重新打开列表。"
        }
    }
}

@MainActor
public final class MemoStore: ObservableObject {
    private struct Document: Codable {
        var version: Int = 4
        var memos: [Memo]
        var deletedMemos: [Memo]?
    }
    @Published public private(set) var memos: [Memo] = []
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var deletedMemos: [Memo] = []
    public var canUndoDeletion: Bool { !deletedMemos.isEmpty }
    public private(set) var recoveryRequired = false
    private let persistence: MemoPersistence
    private let logger = Logger(subsystem: "local.memoline.desktop", category: "storage")

    public init(persistence: MemoPersistence) {
        self.persistence = persistence
        do {
            if let data = try persistence.load() {
                let document = try JSONDecoder().decode(Document.self, from: data)
                guard (1...4).contains(document.version) else { throw MemoStoreError.unsupportedVersion }
                let deleted = document.deletedMemos ?? []
                try Self.validate(document.memos + deleted)
                memos = document.memos
                deletedMemos = deleted
            }
        } catch {
            recoveryRequired = true
            report(error, prefix: "无法读取便签。原文件已保留；请从备份恢复。")
        }
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MemoLine/memos.json")
    }
    public var ropeMemos: [Memo] {
        memos.filter { $0.status != .archived }.sorted {
            let aRinging = $0.reminderState == .ringing
            let bRinging = $1.reminderState == .ringing
            if aRinging != bRinging { return aRinging }
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
    public func listed(status: MemoStatus?, search: String) -> [Memo] {
        memos.filter { (status == nil || $0.status == status) &&
            (search.isEmpty || $0.text.localizedStandardContains(search)) }.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
    public func memo(_ id: UUID) -> Memo? { memos.first { $0.id == id } }
    public func dismissError() { errorMessage = nil }

    @discardableResult public func create(_ draft: Memo) -> Bool {
        var memo = draft
        memo.reconcileTodoItems()
        memo.sortOrder = (memos.map(\.sortOrder).min() ?? 0) - 1
        memo.updatedAt = Date()
        return commit(memos + [memo])
    }
    // Editing only merges editable fields, so an open editor cannot overwrite
    // archive, pin or ordering changes made in another window.
    @discardableResult public func edit(_ id: UUID, text: String, type: MemoType, color: MemoColor,
                                       priority: MemoPriority? = nil) -> Bool {
        mutate(id) { memo in
            let checklistChanged = memo.text != text || memo.type != type
            memo.text = text; memo.type = type; memo.color = color
            if let priority { memo.priority = priority }
            if checklistChanged { memo.reconcileTodoItems() }
            memo.isChecked = type == .todo && memo.status == .completed
        }
    }
    @discardableResult public func setColor(_ id: UUID, _ color: MemoColor) -> Bool { mutate(id) { $0.color = color } }
    @discardableResult public func setPriority(_ id: UUID, _ priority: MemoPriority) -> Bool {
        mutate(id) { $0.priority = priority }
    }
    @discardableResult public func toggleTodoItem(_ id: UUID, itemID: UUID) -> Bool {
        guard let memo = memo(id), memo.type == .todo, memo.status == .active,
              let index = memo.todoItems.firstIndex(where: { $0.id == itemID }) else { return false }
        if !memo.todoItems[index].isChecked && memo.todoItems.filter({ !$0.isChecked }).count == 1 {
            return discard(id)
        }
        return mutate(id) { $0.todoItems[index].isChecked.toggle() }
    }
    @discardableResult public func togglePin(_ id: UUID) -> Bool { mutate(id) { $0.isPinned.toggle() } }
    @discardableResult public func toggleCompleted(_ id: UUID) -> Bool {
        // Completing a pending to-do removes it, with its original state available to Undo.
        if let memo = memo(id), memo.type == .todo, memo.status == .active {
            return discard(id)
        }
        return mutate(id) {
            guard $0.status != .archived else { return }
            $0.status = $0.status == .completed ? .active : .completed
            $0.isChecked = $0.type == .todo && $0.status == .completed
            if $0.status == .completed { Self.clearReminderFields(&$0) }
        }
    }
    @discardableResult public func archive(_ id: UUID) -> Bool {
        mutate(id) { $0.status = .archived; Self.clearReminderFields(&$0) }
    }
    @discardableResult public func restore(_ id: UUID) -> Bool {
        mutate(id) { $0.status = .active; $0.isChecked = false }
    }
    /// MemoLine's simplified rope-only UI has no archive browser. Restore any
    /// notes archived by older releases in one atomic write so they remain visible.
    @discardableResult public func restoreAllArchived() -> Bool {
        guard memos.contains(where: { $0.status == .archived }) else { return true }
        let now = Date()
        let next = memos.map { item -> Memo in
            guard item.status == .archived else { return item }
            var memo = item
            memo.status = .active
            memo.isChecked = false
            memo.updatedAt = now
            return memo
        }
        return commit(next)
    }
    /// Immediate removal for the trash button and to-do completion. Undo is persisted
    /// in the same atomic document; a crash during the visual animation is safe.
    @discardableResult public func discard(_ id: UUID) -> Bool {
        guard var item = memo(id) else { return false }
        Self.clearReminderFields(&item)
        return commit(memos.filter { $0.id != id }, deleted: deletedMemos + [item])
    }
    @discardableResult public func undoDeletion() -> Bool {
        guard let item = deletedMemos.last else { return false }
        return commit(memos + [item], deleted: Array(deletedMemos.dropLast()))
    }
    /// Explicit permanent deletion remains available behind a confirmation dialog.
    @discardableResult public func delete(_ id: UUID) -> Bool {
        commit(memos.filter { $0.id != id }, deleted: deletedMemos.filter { $0.id != id })
    }

    // MARK: Reminders

    @discardableResult public func setReminder(_ id: UUID, date: Date, snoozed: Bool = false) -> Bool {
        mutate(id) {
            guard $0.status == .active else { return }
            $0.reminderDate = snoozed ? ($0.reminderDate ?? date) : date
            $0.reminderState = snoozed ? .snoozed : .scheduled
            $0.snoozedUntil = snoozed ? date : nil
            $0.lastTriggeredAt = nil
            if $0.reminderNotificationID.isEmpty {
                $0.reminderNotificationID = "memoline.memo.\($0.id.uuidString)"
            }
        }
    }

    @discardableResult public func cancelReminder(_ id: UUID) -> Bool {
        mutate(id) { Self.clearReminderFields(&$0) }
    }

    @discardableResult public func triggerDueReminders(at now: Date = Date()) -> Bool {
        var changed = false
        let next = memos.map { item -> Memo in
            var memo = item
            guard memo.status == .active,
                  [.scheduled, .snoozed].contains(memo.reminderState),
                  let date = memo.effectiveReminderDate, date <= now else { return memo }
            memo.reminderState = .ringing
            memo.lastTriggeredAt = now
            memo.updatedAt = now
            changed = true
            return memo
        }
        return changed ? commit(next) : true
    }

    @discardableResult public func acknowledgeReminder(_ id: UUID, at now: Date = Date()) -> Bool {
        mutate(id) {
            guard $0.reminderState == .ringing else { return }
            $0.reminderState = .acknowledged
            $0.lastTriggeredAt = $0.lastTriggeredAt ?? now
            $0.snoozedUntil = nil
        }
    }

    @discardableResult public func snoozeReminder(_ id: UUID, until date: Date) -> Bool {
        setReminder(id, date: date, snoozed: true)
    }
    @discardableResult public func move(_ id: UUID, before targetID: UUID, after: Bool = false) -> Bool {
        guard id != targetID, let source = memo(id), let target = memo(targetID),
              source.isPinned == target.isPinned, source.status != .archived, target.status != .archived else { return false }
        var ordered = ropeMemos.filter { $0.id != id }
        guard let index = ordered.firstIndex(where: { $0.id == targetID }) else { return false }
        ordered.insert(source, at: index + (after ? 1 : 0))
        let positions = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($0.element.id, $0.offset) })
        let next = memos.map { item -> Memo in
            var value = item
            if let position = positions[value.id] { value.sortOrder = position }
            if value.id == id { value.updatedAt = Date() }
            return value
        }
        return commit(next)
    }
    @discardableResult private func mutate(_ id: UUID, body: (inout Memo) -> Void) -> Bool {
        var next = memos
        guard let index = next.firstIndex(where: { $0.id == id }) else {
            report(MemoStoreError.missingMemo); return false
        }
        body(&next[index]); next[index].updatedAt = Date()
        return commit(next)
    }
    private static func clearReminderFields(_ memo: inout Memo) {
        memo.reminderDate = nil
        memo.reminderState = .none
        memo.lastTriggeredAt = nil
        memo.snoozedUntil = nil
    }
    private static func validate(_ memos: [Memo]) throws {
        guard Set(memos.map(\.id)).count == memos.count else { throw MemoStoreError.duplicateID }
        guard memos.allSatisfy({ Set($0.todoItems.map(\.id)).count == $0.todoItems.count }) else {
            throw MemoStoreError.duplicateID
        }
        guard memos.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            $0.text.count <= Memo.characterLimit }) else { throw MemoStoreError.invalidText }
    }
    private func commit(_ next: [Memo], deleted: [Memo]? = nil) -> Bool {
        do {
            guard !recoveryRequired else { throw MemoStoreError.recoveryRequired }
            let undo = deleted ?? deletedMemos
            try Self.validate(next + undo)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try persistence.write(encoder.encode(Document(memos: next, deletedMemos: undo)))
            memos = next; deletedMemos = undo; errorMessage = nil
            return true
        } catch {
            report(error, prefix: "保存失败，已保留此前数据。编辑窗口中的文字仍可重试保存。")
            return false
        }
    }
    private func report(_ error: Error, prefix: String = "操作未完成。") {
        // Never log note text.
        logger.error("Memo storage operation failed: \(error.localizedDescription, privacy: .public)")
        errorMessage = prefix + "\n" + error.localizedDescription
    }
}
