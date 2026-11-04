import Foundation
import MemoCore

private final class MemoryPersistence: MemoPersistence {
    var data: Data?
    var failWrites = false
    var writes = 0
    func load() throws -> Data? { data }
    func write(_ data: Data) throws {
        if failWrites { throw CocoaError(.fileWriteNoPermission) }
        self.data = data; writes += 1
    }
}

final class MemoStoreTests {
    @MainActor func testChecklistAndPriorityPersistence() async {
        let disk = MemoryPersistence(), store = MemoStore(persistence: MemoryPersistence())
        let memo = Memo(text: "买牛奶\n寄快递\n准备资料", type: .todo)
        let saved = MemoStore(persistence: disk)
        expectTrue(saved.create(memo)); expectTrue(saved.setPriority(memo.id, .p1))
        guard let first = saved.memo(memo.id)?.todoItems.first else { expectTrue(false); return }
        expectTrue(saved.toggleTodoItem(memo.id, itemID: first.id))
        let restored = MemoStore(persistence: disk)
        expectEqual(restored.memo(memo.id)?.todoItems.count, 3)
        expectEqual(restored.memo(memo.id)?.todoItems.first?.isChecked, true)
        expectEqual(restored.memo(memo.id)?.priority, .p1)
        expectEqual(restored.memo(memo.id)?.status, .active)
        expectEqual(store.memos.count, 0)
    }

    @MainActor func testChecklistEditPreservesChecksAcrossReorder() async {
        let store = MemoStore(persistence: MemoryPersistence())
        let memo = Memo(text: "A\nB\nC", type: .todo); store.create(memo)
        guard let a = store.memo(memo.id)?.todoItems.first else { expectTrue(false); return }
        store.toggleTodoItem(memo.id, itemID: a.id)
        store.edit(memo.id, text: "C\nA\n新任务", type: .todo, color: .butter, priority: .p2)
        let items = store.memo(memo.id)?.todoItems ?? []
        expectEqual(items.map(\.text), ["C", "A", "新任务"])
        expectEqual(items.first(where: { $0.text == "A" })?.id, a.id)
        expectEqual(items.first(where: { $0.text == "A" })?.isChecked, true)
        expectEqual(items.last?.isChecked, false)
    }

    @MainActor func testChecklistLastCompletionAndWriteFailure() async {
        let disk = MemoryPersistence(), memo = Memo(text: "A\nB", type: .todo)
        let store = MemoStore(persistence: disk); store.create(memo)
        guard let items = store.memo(memo.id)?.todoItems, items.count == 2 else { expectTrue(false); return }
        store.setReminder(memo.id, date: .distantFuture)
        disk.failWrites = true
        expectFalse(store.toggleTodoItem(memo.id, itemID: items[0].id))
        expectEqual(store.memo(memo.id)?.todoItems[0].isChecked, false)
        disk.failWrites = false
        store.toggleTodoItem(memo.id, itemID: items[0].id)
        expectNotNil(store.memo(memo.id))
        expectTrue(store.toggleTodoItem(memo.id, itemID: items[1].id))
        expectNil(store.memo(memo.id)); expectTrue(store.undoDeletion())
        expectEqual(store.memo(memo.id)?.todoItems[0].isChecked, true)
        expectEqual(store.memo(memo.id)?.todoItems[1].isChecked, false)
        expectEqual(store.memo(memo.id)?.reminderState, ReminderState.none)
    }

    @MainActor func testLegacyChecklistMigration() async throws {
        let disk = MemoryPersistence(), store = MemoStore(persistence: MemoryPersistence())
        let memo = Memo(text: "旧任务\n补充说明", type: .todo)
        store.create(memo)
        let encoder = JSONEncoder()
        var object = try JSONSerialization.jsonObject(with: encoder.encode(memo)) as? [String: Any] ?? [:]
        object.removeValue(forKey: "priority"); object.removeValue(forKey: "todoItems")
        disk.data = try JSONSerialization.data(withJSONObject: ["version": 3, "memos": [object]])
        let migrated = MemoStore(persistence: disk)
        expectFalse(migrated.recoveryRequired)
        expectEqual(migrated.memo(memo.id)?.todoItems.count, 1)
        expectEqual(migrated.memo(memo.id)?.todoItems.first?.text, memo.text)
        expectEqual(migrated.memo(memo.id)?.priority, .p3)
        migrated.setPriority(memo.id, .p2)
        expectEqual(MemoStore(persistence: disk).memos, migrated.memos)
    }
    @MainActor func testRoundTripAllFieldsAndStableIdentity() async {
        let disk = MemoryPersistence(), draft = Memo(text: "购物清单 🛒", type: .text, color: .lavender)
        let store = MemoStore(persistence: disk)
        expectTrue(store.create(draft))
        expectTrue(store.togglePin(draft.id)); expectTrue(store.toggleCompleted(draft.id))
        let restored = MemoStore(persistence: disk)
        expectEqual(store.memos, restored.memos)
        expectEqual(restored.memo(draft.id)?.isChecked, false)
        expectEqual(restored.memo(draft.id)?.status, .completed)
    }
    @MainActor func testArchiveRetainsDataAndRestore() async {
        let disk = MemoryPersistence(), memo = Memo(text: "带钥匙")
        let store = MemoStore(persistence: disk); store.create(memo); store.archive(memo.id)
        expectTrue(store.ropeMemos.isEmpty)
        let restored = MemoStore(persistence: disk)
        expectEqual(restored.memos.count, 1)
        expectEqual(restored.memo(memo.id)?.status, .archived)
        restored.restore(memo.id)
        expectEqual(restored.ropeMemos.map(\.id), [memo.id])
    }
    @MainActor func testRopeOnlyMigrationRestoresAllArchivedAtomically() async {
        let disk = MemoryPersistence()
        let first = Memo(text: "旧归档 A"), second = Memo(text: "旧归档 B"), active = Memo(text: "当前")
        let store = MemoStore(persistence: disk)
        [first, second, active].forEach { expectTrue(store.create($0)) }
        expectTrue(store.archive(first.id)); expectTrue(store.archive(second.id))
        expectTrue(store.restoreAllArchived())
        expectEqual(store.memos.filter { $0.status == .archived }.count, 0)
        expectEqual(Set(store.ropeMemos.map(\.id)), Set([first.id, second.id, active.id]))
        let reloaded = MemoStore(persistence: disk)
        expectEqual(reloaded.memos.filter { $0.status == .archived }.count, 0)
    }
    @MainActor func testCapacityNeverEvictsAndPinOrdering() async {
        let store = MemoStore(persistence: MemoryPersistence())
        let first = Memo(text: "永远保留"); store.create(first)
        for n in 0..<120 { store.create(Memo(text: "便签 \(n)")) }
        store.togglePin(first.id)
        expectEqual(store.memos.count, 121)
        expectEqual(store.ropeMemos.first?.id, first.id)
    }
    @MainActor func testReorderPersistsAndRejectsCrossPinGroup() async {
        let disk = MemoryPersistence()
        let s = MemoStore(persistence: disk)
        let a = Memo(text: "A"), b = Memo(text: "B"), c = Memo(text: "C")
        [a,b,c].forEach { s.create($0) }
        expectTrue(s.move(a.id, before: c.id))
        expectEqual(s.ropeMemos.map(\.id), [a.id,c.id,b.id])
        expectTrue(s.move(a.id, before: b.id, after: true))
        expectEqual(MemoStore(persistence: disk).ropeMemos.map(\.id), [c.id,b.id,a.id])
        s.togglePin(a.id)
        expectFalse(s.move(a.id, before: b.id))
    }
    @MainActor func testFailedWriteRollsBackAndCanRetry() async {
        let disk = MemoryPersistence(), memo = Memo(text: "原内容")
        let store = MemoStore(persistence: disk); store.create(memo)
        let saved = disk.data; disk.failWrites = true
        expectFalse(store.edit(memo.id, text: "新内容", type: .text, color: .rose))
        expectEqual(store.memo(memo.id)?.text, "原内容")
        expectEqual(disk.data, saved); expectNotNil(store.errorMessage)
        disk.failWrites = false
        expectTrue(store.edit(memo.id, text: "新内容", type: .text, color: .rose))
        expectNil(store.errorMessage)
    }
    @MainActor func testCorruptFileIsNeverOverwritten() async {
        let disk = MemoryPersistence(); disk.data = Data("broken".utf8)
        let store = MemoStore(persistence: disk)
        expectTrue(store.recoveryRequired)
        expectFalse(store.create(Memo(text: "不要覆盖")))
        expectEqual(disk.data, Data("broken".utf8)); expectEqual(disk.writes, 0)
    }
    @MainActor func testUnsupportedSchemaIsPreserved() async {
        let disk = MemoryPersistence(); disk.data = Data("{\"version\":99,\"memos\":[]}".utf8)
        let store = MemoStore(persistence: disk)
        expectTrue(store.recoveryRequired); expectFalse(store.create(Memo(text: "test")))
        expectEqual(disk.writes, 0)
    }
    @MainActor func testLengthUsesGraphemeClustersAndRejectsEmpty() async {
        let store = MemoStore(persistence: MemoryPersistence())
        expectFalse(store.create(Memo(text: " \n ")))
        expectTrue(store.create(Memo(text: String(repeating: "👨‍👩‍👧‍👦", count: 500))))
        expectFalse(store.create(Memo(text: String(repeating: "中", count: 501))))
        expectEqual(store.memos.count, 1)
    }
    @MainActor func testEditDoesNotOverwriteConcurrentStatusOrOrder() async {
        let store = MemoStore(persistence: MemoryPersistence()), memo = Memo(text: "之前")
        store.create(memo); store.togglePin(memo.id); store.archive(memo.id)
        store.edit(memo.id, text: "修改正文", type: .todo, color: .sky)
        expectEqual(store.memo(memo.id)?.status, .archived)
        expectEqual(store.memo(memo.id)?.isPinned, true)
    }
    @MainActor func testSearchAndListSort() async {
        let store = MemoStore(persistence: MemoryPersistence())
        let first = Memo(text: "Alpha"), second = Memo(text: "Beta ALPHA")
        store.create(first); store.create(second)
        expectEqual(store.listed(status: .active, search: "alpha").map(\.id), [second.id,first.id])
        store.togglePin(first.id)
        expectEqual(store.listed(status: nil, search: "ALPHA").first?.id, first.id)
        store.archive(first.id)
        expectEqual(store.listed(status: .archived, search: "alpha").count, 1)
    }
    @MainActor func testPermanentDeletionAndFailureSafety() async {
        let disk = MemoryPersistence(), memo = Memo(text: "临时")
        let store = MemoStore(persistence: disk); store.create(memo)
        disk.failWrites = true; expectFalse(store.delete(memo.id)); expectEqual(store.memos.count, 1)
        disk.failWrites = false; expectTrue(store.delete(memo.id))
        expectTrue(MemoStore(persistence: disk).memos.isEmpty)
    }
    @MainActor func testAtomicFileStorageAndBackup() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("memos.json")
        let disk = FileMemoPersistence(url: url), store = MemoStore(persistence: FileMemoPersistence(url: url))
        let memo = Memo(text: "磁盘恢复")
        expectTrue(store.create(memo))
        let first = try Data(contentsOf: url)
        expectTrue(store.setColor(memo.id, .sage))
        expectEqual(try Data(contentsOf: url.appendingPathExtension("backup")), first)
        expectEqual(MemoStore(persistence: disk).memo(memo.id)?.color, .sage)
    }
    @MainActor func testDuplicateIDRejected() async {
        let store = MemoStore(persistence: MemoryPersistence()), memo = Memo(text: "唯一")
        expectTrue(store.create(memo)); expectFalse(store.create(memo))
        expectEqual(store.memos.count, 1)
    }
    @MainActor func testTodoCompletionDeletesWithPersistentUndo() async {
        let disk = MemoryPersistence()
        let s = MemoStore(persistence: disk)
        let todo = Memo(text: "寄包裹", type: .todo, color: .sage)
        s.create(todo); s.togglePin(todo.id)
        let original = s.memo(todo.id)
        expectTrue(s.toggleCompleted(todo.id))
        expectNil(s.memo(todo.id)); expectTrue(s.ropeMemos.isEmpty)
        expectTrue(s.canUndoDeletion)
        let restored = MemoStore(persistence: disk)
        expectTrue(restored.canUndoDeletion)
        expectTrue(restored.undoDeletion())
        expectEqual(restored.memo(todo.id), original)
        expectEqual(restored.memo(todo.id)?.status, .active)
        expectFalse(restored.canUndoDeletion)
    }
    @MainActor func testDeletionAndUndoAreAtomicOnFailure() async {
        let disk = MemoryPersistence()
        let store = MemoStore(persistence: disk), todo = Memo(text: "保留", type: .todo)
        store.create(todo); let before = disk.data
        disk.failWrites = true
        expectFalse(store.toggleCompleted(todo.id))
        expectNotNil(store.memo(todo.id)); expectFalse(store.canUndoDeletion); expectEqual(disk.data, before)
        disk.failWrites = false; expectTrue(store.discard(todo.id))
        let deleted = disk.data
        disk.failWrites = true; expectFalse(store.undoDeletion())
        expectNil(store.memo(todo.id)); expectTrue(store.canUndoDeletion); expectEqual(disk.data, deleted)
        disk.failWrites = false; expectTrue(store.undoDeletion())
        expectNotNil(store.memo(todo.id))
    }
    @MainActor func testUndoStackPreservesMultipleDeletesAndOrder() async {
        let disk = MemoryPersistence()
        let s = MemoStore(persistence: disk)
        let a = Memo(text: "A"), b = Memo(text: "B"), c = Memo(text: "C")
        [a,b,c].forEach { s.create($0) }; s.togglePin(a.id)
        let order = s.ropeMemos
        s.discard(a.id); s.discard(b.id)
        expectFalse(s.discard(b.id))
        let restored = MemoStore(persistence: disk)
        expectTrue(restored.undoDeletion()); expectNotNil(restored.memo(b.id))
        expectTrue(restored.undoDeletion()); expectEqual(restored.ropeMemos, order)
        expectFalse(restored.undoDeletion())
    }
    @MainActor func testVersionOneDataMigratesWithoutLoss() async throws {
        let disk = MemoryPersistence(), draft = Memo(text: "旧版数据", type: .todo)
        let store = MemoStore(persistence: disk); store.create(draft)
        guard let data = disk.data, var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            expectTrue(false); return
        }
        json["version"] = 1; json.removeValue(forKey: "deletedMemos")
        disk.data = try JSONSerialization.data(withJSONObject: json)
        let upgraded = MemoStore(persistence: disk)
        expectEqual(upgraded.memos, store.memos); expectFalse(upgraded.recoveryRequired)
        expectTrue(upgraded.discard(draft.id))
        let restarted = MemoStore(persistence: disk)
        expectTrue(restarted.undoDeletion()); expectEqual(restarted.memos, store.memos)
    }

    @MainActor func testReminderPersistsWithStableIdentifier() async {
        let disk = MemoryPersistence(), memo = Memo(text: "缴电费", type: .todo)
        let store = MemoStore(persistence: disk); expectTrue(store.create(memo))
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        expectTrue(store.setReminder(memo.id, date: date))
        let restored = MemoStore(persistence: disk).memo(memo.id)
        expectEqual(restored?.reminderDate, date)
        expectEqual(restored?.reminderState, .scheduled)
        expectEqual(restored?.reminderNotificationID, "memoline.memo.\(memo.id.uuidString)")
    }

    @MainActor func testDueReminderRingsAndAcknowledgementDoesNotComplete() async {
        let store = MemoStore(persistence: MemoryPersistence()), memo = Memo(text: "马上处理", type: .todo)
        store.create(memo)
        let due = Date(timeIntervalSince1970: 1_900_000_000)
        store.setReminder(memo.id, date: due)
        expectTrue(store.triggerDueReminders(at: due.addingTimeInterval(1)))
        expectEqual(store.memo(memo.id)?.reminderState, .ringing)
        expectNotNil(store.memo(memo.id)?.lastTriggeredAt)
        expectTrue(store.acknowledgeReminder(memo.id, at: due.addingTimeInterval(2)))
        expectEqual(store.memo(memo.id)?.reminderState, .acknowledged)
        expectEqual(store.memo(memo.id)?.status, .active)
        expectEqual(store.memo(memo.id)?.isChecked, false)
    }

    @MainActor func testSnoozeReschedulesAndRingsAtNewTime() async {
        let store = MemoStore(persistence: MemoryPersistence()), memo = Memo(text: "休息后处理")
        store.create(memo)
        let original = Date(timeIntervalSince1970: 1_900_000_000)
        let later = original.addingTimeInterval(600)
        store.setReminder(memo.id, date: original)
        store.triggerDueReminders(at: original)
        expectTrue(store.snoozeReminder(memo.id, until: later))
        expectEqual(store.memo(memo.id)?.reminderState, .snoozed)
        expectEqual(store.memo(memo.id)?.effectiveReminderDate, later)
        store.triggerDueReminders(at: later.addingTimeInterval(-1))
        expectEqual(store.memo(memo.id)?.reminderState, .snoozed)
        store.triggerDueReminders(at: later)
        expectEqual(store.memo(memo.id)?.reminderState, .ringing)
    }

    @MainActor func testArchiveCompletionAndDeletionClearReminder() async {
        let store = MemoStore(persistence: MemoryPersistence())
        let archived = Memo(text: "归档"), completed = Memo(text: "完成"), deleted = Memo(text: "删除")
        [archived, completed, deleted].forEach { store.create($0); store.setReminder($0.id, date: .distantFuture) }
        expectTrue(store.archive(archived.id))
        expectTrue(store.toggleCompleted(completed.id))
        expectTrue(store.discard(deleted.id))
        expectEqual(store.memo(archived.id)?.reminderState, ReminderState.none)
        expectNil(store.memo(archived.id)?.reminderDate)
        expectEqual(store.memo(completed.id)?.reminderState, ReminderState.none)
        expectNil(store.memo(completed.id)?.reminderDate)
        expectTrue(store.undoDeletion())
        expectEqual(store.memo(deleted.id)?.reminderState, ReminderState.none)
        expectNil(store.memo(deleted.id)?.reminderDate)
    }

    @MainActor func testMultipleDueRemindersRingTogetherAndSortFirst() async {
        let store = MemoStore(persistence: MemoryPersistence())
        let a = Memo(text: "A"), b = Memo(text: "B"), future = Memo(text: "以后")
        [a, b, future].forEach { store.create($0) }
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        store.setReminder(a.id, date: now); store.setReminder(b.id, date: now)
        store.setReminder(future.id, date: now.addingTimeInterval(60))
        store.triggerDueReminders(at: now)
        expectEqual(Set(store.memos.filter { $0.reminderState == .ringing }.map(\.id)), Set([a.id, b.id]))
        expectEqual(Set(store.ropeMemos.prefix(2).map(\.id)), Set([a.id, b.id]))
        store.acknowledgeReminder(a.id)
        expectEqual(store.memo(b.id)?.reminderState, .ringing)
    }

}
