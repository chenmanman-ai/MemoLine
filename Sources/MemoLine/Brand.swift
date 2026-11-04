import AppKit

enum Brand {
    /// A system template symbol remains legible in light/dark menu bars and
    /// under increased-contrast settings. It also occupies less menu-bar room.
    static func statusIcon(hasRingingReminder: Bool = false) -> NSImage {
        let image = NSImage(
            systemSymbolName: hasRingingReminder ? "bell.badge.fill" : "note.text",
            accessibilityDescription: "MemoLine 便签菜单"
        ) ?? NSImage(size: NSSize(width: 18, height: 18))
        image.isTemplate = true
        return image
    }
}
