import AppKit
import MemoCore
import SwiftUI

enum ReminderDates {
    static func todayLater(from now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let plusTwo = calendar.date(byAdding: .hour, value: 2, to: now) ?? now.addingTimeInterval(7200)
        if calendar.isDate(plusTwo, inSameDayAs: now) { return plusTwo }
        let late = calendar.date(bySettingHour: 23, minute: 30, second: 0, of: now) ?? plusTwo
        return late > now ? late : now.addingTimeInterval(30 * 60)
    }

    static func tomorrow(from now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86400)
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }

    static func snooze(_ minutes: Int, from now: Date = Date()) -> Date {
        now.addingTimeInterval(TimeInterval(minutes * 60))
    }

    static func label(for memo: Memo, now: Date = Date()) -> String? {
        if memo.reminderState == .ringing { return "提醒正在响铃" }
        if memo.reminderState == .acknowledged { return "已提醒" }
        guard let date = memo.effectiveReminderDate else { return nil }
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "今天 \(time)" }
        if calendar.isDateInTomorrow(date) { return "明天 \(time)" }
        return date.formatted(.dateTime.month(.defaultDigits).day().hour().minute())
    }
}

@MainActor
enum ReminderPrompt {
    static func chooseDate(current: Date?) -> Date? {
        let picker = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 250, height: 28))
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.yearMonthDay, .hourMinute]
        picker.minDate = Date().addingTimeInterval(60)
        picker.dateValue = max(current ?? Date().addingTimeInterval(3600), picker.minDate ?? Date())
        picker.setAccessibilityLabel("提醒日期和时间")
        let alert = NSAlert()
        alert.messageText = "选择提醒时间"
        alert.informativeText = "提醒只会触发一次。"
        alert.accessoryView = picker
        alert.addButton(withTitle: "设置提醒")
        alert.addButton(withTitle: "取消")
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn ? picker.dateValue : nil
    }

    static func present(for memo: Memo, store: MemoStore) {
        if let date = chooseDate(current: memo.effectiveReminderDate) {
            store.setReminder(memo.id, date: date)
        }
    }
}

struct ReminderMenuItems: View {
    let memo: Memo
    @ObservedObject var store: MemoStore

    var body: some View {
        Button("今天稍后") { store.setReminder(memo.id, date: ReminderDates.todayLater()) }
        Button("明天 09:00") { store.setReminder(memo.id, date: ReminderDates.tomorrow()) }
        Button("选择日期和时间…") {
            if let date = ReminderPrompt.chooseDate(current: memo.effectiveReminderDate) {
                store.setReminder(memo.id, date: date)
            }
        }
        if memo.reminderState != .none {
            Divider()
            Menu("稍后提醒") {
                Button("10 分钟后") { store.snoozeReminder(memo.id, until: ReminderDates.snooze(10)) }
                Button("30 分钟后") { store.snoozeReminder(memo.id, until: ReminderDates.snooze(30)) }
                Button("1 小时后") { store.snoozeReminder(memo.id, until: ReminderDates.snooze(60)) }
                Button("明天") { store.snoozeReminder(memo.id, until: ReminderDates.tomorrow()) }
            }
            Button("取消提醒") { store.cancelReminder(memo.id) }
        }
    }
}
