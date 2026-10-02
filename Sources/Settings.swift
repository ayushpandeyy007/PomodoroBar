import Foundation

enum Phase: String {
    case focus, shortBreak, longBreak

    var title: String {
        switch self {
        case .focus: "Focus"
        case .shortBreak: "Short Break"
        case .longBreak: "Long Break"
        }
    }

    var isBreak: Bool { self != .focus }
}

/// Typed wrapper over UserDefaults. Everything persists across launches.
@MainActor
final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            "focusMinutes": 25,
            "shortBreakMinutes": 5,
            "longBreakMinutes": 15,
            "longBreakEvery": 4,
            "autoStartBreaks": true,
            "autoStartFocus": false,
            "playSound": true,
            "showTimeInMenuBar": true,
            "globalShortcut": true,
        ])
    }

    func minutes(for phase: Phase) -> Int { max(1, defaults.integer(forKey: phase.rawValue + "Minutes")) }
    func setMinutes(_ value: Int, for phase: Phase) { defaults.set(value, forKey: phase.rawValue + "Minutes") }

    var longBreakEvery: Int {
        get { max(1, defaults.integer(forKey: "longBreakEvery")) }
        set { defaults.set(newValue, forKey: "longBreakEvery") }
    }
    var autoStartBreaks: Bool {
        get { defaults.bool(forKey: "autoStartBreaks") }
        set { defaults.set(newValue, forKey: "autoStartBreaks") }
    }
    var autoStartFocus: Bool {
        get { defaults.bool(forKey: "autoStartFocus") }
        set { defaults.set(newValue, forKey: "autoStartFocus") }
    }
    var playSound: Bool {
        get { defaults.bool(forKey: "playSound") }
        set { defaults.set(newValue, forKey: "playSound") }
    }
    var showTimeInMenuBar: Bool {
        get { defaults.bool(forKey: "showTimeInMenuBar") }
        set { defaults.set(newValue, forKey: "showTimeInMenuBar") }
    }
    var globalShortcut: Bool {
        get { defaults.bool(forKey: "globalShortcut") }
        set { defaults.set(newValue, forKey: "globalShortcut") }
    }

    // MARK: Today's stats (roll over automatically at midnight)

    private var todayKey: Int {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return (c.year ?? 0) * 10_000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    var today: (count: Int, focusSeconds: Int) {
        guard defaults.integer(forKey: "statsDay") == todayKey else { return (0, 0) }
        return (defaults.integer(forKey: "statsCount"), defaults.integer(forKey: "statsFocusSeconds"))
    }

    func recordFocusSession(seconds: Int) {
        let current = today
        defaults.set(todayKey, forKey: "statsDay")
        defaults.set(current.count + 1, forKey: "statsCount")
        defaults.set(current.focusSeconds + seconds, forKey: "statsFocusSeconds")
    }
}
