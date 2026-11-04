import Foundation

// Dependency-free regression runner: also runs on Command Line Tools without XCTest.
@MainActor private var failures = 0
@MainActor func expectTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    if !value { failures += 1; print("FAIL \(file):\(line): expected true") }
}
@MainActor func expectFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { expectTrue(!value, file: file, line: line) }
@MainActor func expectEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { expectTrue(a == b, file: file, line: line) }
@MainActor func expectNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { expectTrue(value == nil, file: file, line: line) }
@MainActor func expectNotNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { expectTrue(value != nil, file: file, line: line) }

@main struct RegressionRunner {
    @MainActor static func main() async {
        let tests = MemoStoreTests()
        do {
            let before = failures
            await tests.testRoundTripAllFieldsAndStableIdentity()
            print("\(failures == before ? "PASS" : "FAIL") testRoundTripAllFieldsAndStableIdentity")
        }
        do {
            let before = failures
            await tests.testArchiveRetainsDataAndRestore()
            print("\(failures == before ? "PASS" : "FAIL") testArchiveRetainsDataAndRestore")
        }
        do {
            let before = failures
            await tests.testRopeOnlyMigrationRestoresAllArchivedAtomically()
            print("\(failures == before ? "PASS" : "FAIL") testRopeOnlyMigrationRestoresAllArchivedAtomically")
        }
        do {
            let before = failures
            await tests.testCapacityNeverEvictsAndPinOrdering()
            print("\(failures == before ? "PASS" : "FAIL") testCapacityNeverEvictsAndPinOrdering")
        }
        do {
            let before = failures
            await tests.testReorderPersistsAndRejectsCrossPinGroup()
            print("\(failures == before ? "PASS" : "FAIL") testReorderPersistsAndRejectsCrossPinGroup")
        }
        do {
            let before = failures
            await tests.testFailedWriteRollsBackAndCanRetry()
            print("\(failures == before ? "PASS" : "FAIL") testFailedWriteRollsBackAndCanRetry")
        }
        do {
            let before = failures
            await tests.testCorruptFileIsNeverOverwritten()
            print("\(failures == before ? "PASS" : "FAIL") testCorruptFileIsNeverOverwritten")
        }
        do {
            let before = failures
            await tests.testUnsupportedSchemaIsPreserved()
            print("\(failures == before ? "PASS" : "FAIL") testUnsupportedSchemaIsPreserved")
        }
        do {
            let before = failures
            await tests.testLengthUsesGraphemeClustersAndRejectsEmpty()
            print("\(failures == before ? "PASS" : "FAIL") testLengthUsesGraphemeClustersAndRejectsEmpty")
        }
        do {
            let before = failures
            await tests.testEditDoesNotOverwriteConcurrentStatusOrOrder()
            print("\(failures == before ? "PASS" : "FAIL") testEditDoesNotOverwriteConcurrentStatusOrOrder")
        }
        do {
            let before = failures
            await tests.testSearchAndListSort()
            print("\(failures == before ? "PASS" : "FAIL") testSearchAndListSort")
        }
        do {
            let before = failures
            await tests.testPermanentDeletionAndFailureSafety()
            print("\(failures == before ? "PASS" : "FAIL") testPermanentDeletionAndFailureSafety")
        }
        do {
            let before = failures
            try await tests.testAtomicFileStorageAndBackup()
            print("\(failures == before ? "PASS" : "FAIL") testAtomicFileStorageAndBackup")
        } catch { failures += 1; print("FAIL unexpected error: \(error)") }
        do {
            let before = failures
            await tests.testDuplicateIDRejected()
            print("\(failures == before ? "PASS" : "FAIL") testDuplicateIDRejected")
        }
        do {
            let before = failures
            await tests.testTodoCompletionDeletesWithPersistentUndo()
            print("\(failures == before ? "PASS" : "FAIL") testTodoCompletionDeletesWithPersistentUndo")
        }
        do {
            let before = failures
            await tests.testDeletionAndUndoAreAtomicOnFailure()
            print("\(failures == before ? "PASS" : "FAIL") testDeletionAndUndoAreAtomicOnFailure")
        }
        do {
            let before = failures
            await tests.testUndoStackPreservesMultipleDeletesAndOrder()
            print("\(failures == before ? "PASS" : "FAIL") testUndoStackPreservesMultipleDeletesAndOrder")
        }
        do {
            let before = failures
            try await tests.testVersionOneDataMigratesWithoutLoss()
            print("\(failures == before ? "PASS" : "FAIL") testVersionOneDataMigratesWithoutLoss")
        } catch { failures += 1; print("FAIL unexpected error: \(error)") }
        do {
            let before = failures
            await tests.testReminderPersistsWithStableIdentifier()
            print("\(failures == before ? "PASS" : "FAIL") testReminderPersistsWithStableIdentifier")
        }
        do {
            let before = failures
            await tests.testDueReminderRingsAndAcknowledgementDoesNotComplete()
            print("\(failures == before ? "PASS" : "FAIL") testDueReminderRingsAndAcknowledgementDoesNotComplete")
        }
        do {
            let before = failures
            await tests.testSnoozeReschedulesAndRingsAtNewTime()
            print("\(failures == before ? "PASS" : "FAIL") testSnoozeReschedulesAndRingsAtNewTime")
        }
        do {
            let before = failures
            await tests.testArchiveCompletionAndDeletionClearReminder()
            print("\(failures == before ? "PASS" : "FAIL") testArchiveCompletionAndDeletionClearReminder")
        }
        do {
            let before = failures
            await tests.testMultipleDueRemindersRingTogetherAndSortFirst()
            print("\(failures == before ? "PASS" : "FAIL") testMultipleDueRemindersRingTogetherAndSortFirst")
        }
        do {
            let before = failures
            await tests.testChecklistAndPriorityPersistence()
            await tests.testChecklistEditPreservesChecksAcrossReorder()
            await tests.testChecklistLastCompletionAndWriteFailure()
            try await tests.testLegacyChecklistMigration()
            print("\(failures == before ? "PASS" : "FAIL") 4 checklist / priority / migration tests")
        } catch { failures += 1; print("FAIL unexpected error: \(error)") }
        print("27 tests; \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
