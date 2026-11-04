import Foundation

public enum MemoType: String, Codable, CaseIterable { case text, todo }
public enum MemoStatus: String, Codable, CaseIterable { case active, completed, archived }
public enum MemoColor: String, Codable, CaseIterable { case butter, rose, sage, sky, lavender }
public enum MemoPriority: Int, Codable, CaseIterable { case p1 = 1, p2, p3, p4, p5 }

public struct TodoItem: Identifiable, Codable, Equatable {
    public let id: UUID
    public var text: String
    public var isChecked: Bool
    public init(id: UUID = UUID(), text: String, isChecked: Bool = false) {
        self.id = id; self.text = text; self.isChecked = isChecked
    }
}
public enum ReminderState: String, Codable, CaseIterable {
    case none, scheduled, ringing, acknowledged, snoozed
}

public struct Memo: Identifiable, Codable, Equatable {
    public let id: UUID
    public var text: String
    public var type: MemoType
    public var isChecked: Bool
    public var color: MemoColor
    public var isPinned: Bool
    public var status: MemoStatus
    public let createdAt: Date
    public var updatedAt: Date
    public var sortOrder: Int
    public var priority: MemoPriority
    public var todoItems: [TodoItem]
    public var reminderDate: Date?
    public var reminderState: ReminderState
    public var reminderNotificationID: String
    public var lastTriggeredAt: Date?
    public var snoozedUntil: Date?
    public static let characterLimit = 500

    public init(id: UUID = UUID(), text: String = "", type: MemoType = .text,
                color: MemoColor = .butter, now: Date = Date(), sortOrder: Int = 0) {
        self.id = id; self.text = text; self.type = type; self.color = color
        isChecked = false; isPinned = false; status = .active
        createdAt = now; updatedAt = now; self.sortOrder = sortOrder
        priority = .p3
        todoItems = type == .todo ? text.split(separator: "\n").map { TodoItem(text: String($0)) } : []
        reminderDate = nil; reminderState = .none
        reminderNotificationID = "memoline.memo.\(id.uuidString)"
        lastTriggeredAt = nil; snoozedUntil = nil
    }

    public var effectiveReminderDate: Date? {
        reminderState == .snoozed ? (snoozedUntil ?? reminderDate) : reminderDate
    }

    /// Exact matches retain IDs and checkmarks, including when lines are reordered.
    /// Changed/new lines start unchecked; editing a task never silently completes it.
    public mutating func reconcileTodoItems() {
        guard type == .todo else { todoItems = []; return }
        var available = todoItems
        todoItems = text.components(separatedBy: .newlines).compactMap { line in
            let cleaned = line.trimmingCharacters(in: .whitespaces)
            guard !cleaned.isEmpty else { return nil }
            if let index = available.firstIndex(where: { $0.text == cleaned }) {
                return available.remove(at: index)
            }
            return TodoItem(text: cleaned)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, type, isChecked, color, isPinned, status, createdAt, updatedAt, sortOrder
        case reminderDate, reminderState, reminderNotificationID, lastTriggeredAt, snoozedUntil
        case priority, todoItems
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        text = try values.decode(String.self, forKey: .text)
        type = try values.decode(MemoType.self, forKey: .type)
        isChecked = try values.decode(Bool.self, forKey: .isChecked)
        color = try values.decode(MemoColor.self, forKey: .color)
        isPinned = try values.decode(Bool.self, forKey: .isPinned)
        status = try values.decode(MemoStatus.self, forKey: .status)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        sortOrder = try values.decode(Int.self, forKey: .sortOrder)
        priority = try values.decodeIfPresent(MemoPriority.self, forKey: .priority) ?? .p3
        // Legacy notes were one task, even if their text contained line breaks.
        todoItems = try values.decodeIfPresent([TodoItem].self, forKey: .todoItems)
            ?? (type == .todo ? [TodoItem(id: id, text: text, isChecked: isChecked)] : [])
        reminderDate = try values.decodeIfPresent(Date.self, forKey: .reminderDate)
        reminderState = try values.decodeIfPresent(ReminderState.self, forKey: .reminderState) ?? .none
        reminderNotificationID = try values.decodeIfPresent(String.self, forKey: .reminderNotificationID)
            ?? "memoline.memo.\(id.uuidString)"
        lastTriggeredAt = try values.decodeIfPresent(Date.self, forKey: .lastTriggeredAt)
        snoozedUntil = try values.decodeIfPresent(Date.self, forKey: .snoozedUntil)
    }
}
