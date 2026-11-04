import AppKit

/// Public window metadata only: no image capture, window titles, AX or private CGS.
/// Conservative fallback: a borderless window covering a display also blocks the line.
@MainActor
final class FullScreenPolicy {
    private var lastProbe = Date.distantPast
    private var cachedScreen: NSScreen?
    private var cachedResult = false
    private var externalPID: pid_t?

    func invalidate() { lastProbe = .distantPast }

    func blocks(_ screen: NSScreen) -> Bool {
        if Preferences.showOverFullScreen { return false }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let own = ProcessInfo.processInfo.processIdentifier
        if let front, front != own, front != externalPID {
            externalPID = front; lastProbe = .distantPast
        }
        if cachedScreen == screen, Date().timeIntervalSince(lastProbe) < 0.5 { return cachedResult }
        cachedScreen = screen; lastProbe = Date()
        guard let primary = NSScreen.screens.first else { return false }
        // Quartz is top-left based on the primary display; AppKit uses bottom-left.
        let target = CGRect(x: screen.frame.minX, y: primary.frame.maxY - screen.frame.maxY,
                            width: screen.frame.width, height: screen.frame.height).insetBy(dx: 2, dy: 2)
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            // On unavailable metadata, avoid surprising full-screen overlays.
            cachedResult = true; return true
        }
        cachedResult = windows.contains { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int, pid != Int(own),
                  externalPID == nil || pid == Int(externalPID ?? 0),
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let dictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary) else { return false }
            return bounds.contains(target)
        }
        return cachedResult
    }
}
