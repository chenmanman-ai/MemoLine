import AppKit
import Combine
import MemoCore
import UserNotifications

@MainActor
final class ReminderController: NSObject, UNUserNotificationCenterDelegate {
    static let stopAction = "MEMOLINE_STOP"
    static let snoozeAction = "MEMOLINE_SNOOZE_10"
    static let completeAction = "MEMOLINE_COMPLETE"
    static let category = "MEMOLINE_REMINDER"

    private let store: MemoStore
    private let center = UNUserNotificationCenter.current()
    private var timer: Timer?
    private var cancellable: AnyCancellable?
    private var knownScheduleKeys: Set<String> = []
    private var loopSound: NSSound?
    private(set) var ringingIDs: Set<UUID> = []

    var onFocusMemo: ((UUID) -> Void)?
    var onRingingChanged: ((Set<UUID>) -> Void)?
    var onPermissionLimited: ((String) -> Void)?

    init(store: MemoStore) {
        self.store = store
        super.init()
    }

    func start() {
        center.delegate = self
        registerCategory()
        knownScheduleKeys = scheduleKeys(store.memos)
        store.triggerDueReminders()
        updateRingingState()
        reconcileNotifications()
        cancellable = store.$memos.dropFirst().sink { [weak self] memos in
            MainActor.assumeIsolated {
                guard let self else { return }
                let keys = self.scheduleKeys(memos)
                let userCreatedSchedule = !keys.subtracting(self.knownScheduleKeys).isEmpty
                self.knownScheduleKeys = keys
                self.updateRingingState()
                self.scheduleNextDueCheck()
                if userCreatedSchedule { self.requestPermissionIfNeeded() }
                else { self.reconcileNotifications() }
            }
        }
        scheduleNextDueCheck()
    }

    func stop() {
        timer?.invalidate(); timer = nil
        cancellable = nil
        stopLoopSound()
        center.delegate = nil
    }

    private func checkDueReminders() {
        let before = ringingIDs
        store.triggerDueReminders()
        updateRingingState()
        if let first = ringingIDs.subtracting(before).first { onFocusMemo?(first) }
        scheduleNextDueCheck()
    }

    /// UserNotifications handles a fully quit app. While running, wake exactly
    /// once for the nearest memo instead of scanning all memos every second.
    private func scheduleNextDueCheck() {
        timer?.invalidate(); timer = nil
        let next = store.memos.compactMap { memo -> Date? in
            guard memo.status == .active,
                  [.scheduled, .snoozed].contains(memo.reminderState) else { return nil }
            return memo.effectiveReminderDate
        }.filter { $0 > Date() }.min()
        guard let next else { return }
        let interval = max(0.1, next.timeIntervalSinceNow)
        timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkDueReminders() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    private func updateRingingState() {
        let next = Set(store.memos.filter {
            $0.status == .active && $0.reminderState == .ringing
        }.map(\.id))
        guard next != ringingIDs else { return }
        ringingIDs = next
        if next.isEmpty { stopLoopSound() } else { startLoopSound() }
        onRingingChanged?(next)
    }

    private func startLoopSound() {
        guard loopSound == nil else { return }
        let sound = RadarAlarmSound.make()
            ?? NSSound(named: NSSound.Name("Alarm"))
            ?? NSSound(named: NSSound.Name("Funk"))
            ?? NSSound(named: NSSound.Name("Glass"))
        sound?.volume = 0.62
        sound?.loops = true
        sound?.play()
        loopSound = sound
    }

    private func stopLoopSound() {
        loopSound?.stop()
        loopSound = nil
    }

    private func registerCategory() {
        let stop = UNNotificationAction(identifier: Self.stopAction, title: "停止提醒")
        let snooze = UNNotificationAction(identifier: Self.snoozeAction, title: "10 分钟后提醒")
        let complete = UNNotificationAction(identifier: Self.completeAction, title: "标记完成")
        let category = UNNotificationCategory(identifier: Self.category,
            actions: [stop, snooze, complete], intentIdentifiers: [])
        center.setNotificationCategories([category])
    }

    private func requestPermissionIfNeeded() {
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            switch settings.authorizationStatus {
            case .notDetermined:
                self.center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                    Task { @MainActor in
                        if !granted {
                            self.onPermissionLimited?(error?.localizedDescription
                                ?? "通知权限未开启。MemoLine 仍会在应用运行时响铃。")
                        }
                        self.reconcileNotifications()
                    }
                }
            case .denied:
                Task { @MainActor in
                    self.onPermissionLimited?("通知权限已被拒绝。MemoLine 只能在应用运行时提醒；可在系统设置的“通知”中开启。")
                    self.reconcileNotifications()
                }
            default:
                Task { @MainActor in self.reconcileNotifications() }
            }
        }
    }

    private func reconcileNotifications() {
        let active = store.memos.filter {
            $0.status == .active && [.scheduled, .snoozed].contains($0.reminderState)
                && ($0.effectiveReminderDate ?? .distantPast) > Date()
        }
        center.getPendingNotificationRequests { [weak self] requests in
            guard let self else { return }
            let managed = requests.map(\.identifier).filter { $0.hasPrefix("memoline.memo.") }
            self.center.removePendingNotificationRequests(withIdentifiers: managed)
            self.center.getNotificationSettings { settings in
                guard [.authorized, .provisional].contains(settings.authorizationStatus) else { return }
                for memo in active { self.addNotification(for: memo) }
            }
        }
        let validIDs = Set(store.memos.filter {
            $0.status == .active && $0.reminderState != .none
        }.map(\.reminderNotificationID))
        center.getDeliveredNotifications { [weak self] notifications in
            let obsolete = notifications.map(\.request.identifier).filter {
                $0.hasPrefix("memoline.memo.") && !validIDs.contains($0)
            }
            self?.center.removeDeliveredNotifications(withIdentifiers: obsolete)
        }
    }

    private func addNotification(for memo: Memo) {
        guard let date = memo.effectiveReminderDate else { return }
        let content = UNMutableNotificationContent()
        let oneLine = memo.text.replacingOccurrences(of: "\n", with: " ")
        content.title = String(oneLine.prefix(60))
        content.body = memo.type == .todo ? "这个待办已经到期。" : "这张便签的提醒时间到了。"
        content.sound = .default
        content.categoryIdentifier = Self.category
        content.userInfo = ["memoID": memo.id.uuidString]
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        center.add(UNNotificationRequest(identifier: memo.reminderNotificationID,
                                          content: content, trigger: trigger))
    }

    private func scheduleKeys(_ memos: [Memo]) -> Set<String> {
        Set(memos.compactMap { memo in
            guard memo.status == .active,
                  [.scheduled, .snoozed].contains(memo.reminderState),
                  let date = memo.effectiveReminderDate else { return nil }
            return "\(memo.reminderNotificationID)|\(date.timeIntervalSince1970)"
        })
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void) {
        let rawID = response.notification.request.content.userInfo["memoID"] as? String
        Task { @MainActor [weak self] in
            defer { completionHandler() }
            guard let self, let rawID, let id = UUID(uuidString: rawID),
                  let memo = self.store.memo(id), memo.status == .active else { return }
            // A notification action can cold-launch the app while the persisted
            // memo is still scheduled. Materialize all due states before applying
            // the selected action so "停止提醒" also works after a full quit.
            self.store.triggerDueReminders()
            switch response.actionIdentifier {
            case Self.stopAction:
                self.store.acknowledgeReminder(id)
            case Self.snoozeAction:
                self.store.snoozeReminder(id, until: Date().addingTimeInterval(10 * 60))
            case Self.completeAction:
                self.store.toggleCompleted(id)
            default:
                NSApp.activate(ignoringOtherApps: true)
                self.onFocusMemo?(id)
            }
        }
    }
}
