import AppKit

enum MemoCardSize: String, CaseIterable {
    case large, medium, small

    var title: String {
        switch self { case .large: "大"; case .medium: "中"; case .small: "小" }
    }
    var scale: CGFloat {
        switch self { case .large: 1.08; case .medium: 1.0; case .small: 0.78 }
    }
}

enum Preferences {
    static var alwaysVisible: Bool {
        get { UserDefaults.standard.bool(forKey: "alwaysVisible") }
        set { UserDefaults.standard.set(newValue, forKey: "alwaysVisible") }
    }
    static var showOverFullScreen: Bool {
        get { UserDefaults.standard.bool(forKey: "showOverFullScreen") }
        set { UserDefaults.standard.set(newValue, forKey: "showOverFullScreen") }
    }
    static var deletionSoundEnabled: Bool {
        get { !UserDefaults.standard.bool(forKey: "deletionSoundOff") }
        set { UserDefaults.standard.set(!newValue, forKey: "deletionSoundOff") }
    }
    static var cardSize: MemoCardSize {
        get { MemoCardSize(rawValue: UserDefaults.standard.string(forKey: "memoCardSize") ?? "") ?? .medium }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "memoCardSize") }
    }
}
