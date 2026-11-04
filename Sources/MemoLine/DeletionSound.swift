import AppKit

@MainActor
enum DeletionSound {
    private static let trashPath = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/dock/drag to trash.aif"
    private static let sound: NSSound? = {
        if let trash = NSSound(contentsOfFile: trashPath, byReference: true) {
            return trash
        }
        return NSSound(named: NSSound.Name("Pop"))
    }()

    static func play() {
        guard Preferences.deletionSoundEnabled, let sound else { return }
        sound.stop()
        sound.volume = 0.42
        sound.play()
    }
}
