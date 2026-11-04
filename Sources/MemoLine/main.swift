import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    #if DEBUG
    if CommandLine.arguments.contains("--verify-new-card") {
        do { try DesignPreview.verifyNewCard(); exit(0) }
        catch { print(error.localizedDescription); exit(1) }
    }
    if CommandLine.arguments.contains("--verify-inline-editor") {
        do { try DesignPreview.verifyInlineEditor(); exit(0) }
        catch { print(error.localizedDescription); exit(1) }
    }
    if let index = CommandLine.arguments.firstIndex(of: "--render-design-preview"),
       CommandLine.arguments.indices.contains(index + 1) {
        do {
            try DesignPreview.render(to: CommandLine.arguments[index + 1], dark: CommandLine.arguments.contains("--dark"))
            exit(0)
        } catch { print(error.localizedDescription); exit(1) }
    }
    #endif
    let delegate = AppDelegate()
    app.delegate = delegate
    // Keep the status item, while also offering a Dock icon and a standard
    // application menu as a reliable fallback on crowded/notched menu bars.
    app.setActivationPolicy(.regular)
    withExtendedLifetime(delegate) { app.run() }
}
