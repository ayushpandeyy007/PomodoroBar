import AppKit
import Carbon.HIToolbox
import ServiceManagement

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    // NSApplication.delegate is weak; keep the delegate alive for the app's lifetime.
    private static var shared: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        shared = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
        app.run()
    }

    private let settings = Settings.shared
    private lazy var engine = PomodoroEngine(settings: settings)
    private let notifier = Notifier()
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var sound: NSSound?

    // Last values pushed to the status button. AppKit is only touched when these change.
    private var shownIcon = -1
    private var shownTitle: String?
    private lazy var clockFont = NSFont.monospacedDigitSystemFont(
        ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)

    // MARK: Menu items updated at runtime

    private let menu = NSMenu()
    private var isMenuOpen = false
    private let headerItem = NSMenuItem()
    private let detailItem = NSMenuItem()
    private let statsItem = NSMenuItem()
    private lazy var toggleItem = makeItem("Start", #selector(toggleTimer))
    private lazy var resetItem = makeItem("Reset Timer", #selector(resetTimer))
    private lazy var skipItem = makeItem("Skip", #selector(skipPhase))
    private var durationItems: [(phase: Phase, item: NSMenuItem)] = []
    private let cycleItem = NSMenuItem()
    private lazy var autoBreaksItem = makeItem("Auto-start Breaks", #selector(toggleAutoBreaks))
    private lazy var autoFocusItem = makeItem("Auto-start Focus", #selector(toggleAutoFocus))
    private lazy var soundItem = makeItem("Play Sound", #selector(toggleSound))
    private lazy var showTimeItem = makeItem("Show Time in Menu Bar", #selector(toggleShowTime))
    private lazy var shortcutItem = makeItem("Global Shortcut (⌃⌥P)", #selector(toggleShortcut))
    private lazy var loginItem = makeItem("Launch at Login", #selector(toggleLaunchAtLogin))

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading
        buildMenu()
        statusItem.menu = menu

        engine.onChange = { [weak self] in self?.render() }
        engine.onPhaseEnd = { [weak self] finished, next, autoStarted in
            self?.phaseEnded(finished: finished, next: next, autoStarted: autoStarted)
        }
        notifier.onStart = { [weak self] in self?.engine.start() }
        notifier.setUp()

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        updateHotKey()
        render()
    }

    @objc private func systemDidWake() { engine.resync() }

    private func phaseEnded(finished: Phase, next: Phase, autoStarted: Bool) {
        if settings.playSound {
            sound = NSSound(named: finished == .focus ? "Glass" : "Hero")
            sound?.play()
        }
        notifier.post(finished: finished, next: next, minutes: settings.minutes(for: next), autoStarted: autoStarted)
    }

    // MARK: Status bar rendering (called at most once per second)

    private func render() {
        guard let button = statusItem.button else { return }

        // The icon has 60 visual steps, so it's redrawn only when a step changes (~every 25s for a 25-min session).
        let step = Int((engine.fractionRemaining * 60).rounded(.up))
        let iconKey = step * 2 + (engine.phase.isBreak ? 1 : 0)
        if iconKey != shownIcon {
            button.image = StatusIcon.image(fraction: Double(step) / 60, isBreak: engine.phase.isBreak)
            shownIcon = iconKey
        }

        let title = settings.showTimeInMenuBar && engine.state != .idle ? " " + Format.clock(engine.remaining) : ""
        if title != shownTitle {
            button.attributedTitle = NSAttributedString(string: title, attributes: [.font: clockFont])
            shownTitle = title
        }

        if button.appearsDisabled != engine.isPaused { button.appearsDisabled = engine.isPaused }
        if isMenuOpen { refreshLiveItems() }
    }

    // MARK: Menu

    private func buildMenu() {
        menu.delegate = self
        menu.autoenablesItems = false
        for info in [headerItem, detailItem, statsItem] { info.isEnabled = false }

        menu.addItem(headerItem)
        menu.addItem(detailItem)
        menu.addItem(.separator())
        toggleItem.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(toggleItem)
        menu.addItem(resetItem)
        menu.addItem(skipItem)
        menu.addItem(.separator())
        menu.addItem(statsItem)
        menu.addItem(.separator())
        menu.addItem(durationMenu(.focus, presets: [15, 20, 25, 30, 40, 45, 50, 60, 90]))
        menu.addItem(durationMenu(.shortBreak, presets: [3, 5, 10, 15]))
        menu.addItem(durationMenu(.longBreak, presets: [10, 15, 20, 25, 30]))

        let cycleMenu = NSMenu()
        for count in 2...8 {
            let item = makeItem("\(count) Focus Sessions", #selector(pickCycleLength(_:)))
            item.tag = count
            cycleMenu.addItem(item)
        }
        cycleItem.submenu = cycleMenu
        menu.addItem(cycleItem)
        menu.addItem(.separator())

        for item in [autoBreaksItem, autoFocusItem, soundItem, showTimeItem, shortcutItem, loginItem] {
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit PomodoroBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func durationMenu(_ phase: Phase, presets: [Int]) -> NSMenuItem {
        let submenu = NSMenu()
        for minutes in presets {
            let item = makeItem("\(minutes) min", #selector(pickDuration(_:)))
            item.tag = minutes
            item.representedObject = phase.rawValue
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        let custom = makeItem("Custom…", #selector(pickDuration(_:)))
        custom.tag = 0
        custom.representedObject = phase.rawValue
        submenu.addItem(custom)

        let parent = NSMenuItem()
        parent.submenu = submenu
        durationItems.append((phase, parent))
        return parent
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshLiveItems()
        refreshSettingsItems()
    }

    func menuWillOpen(_ menu: NSMenu) { isMenuOpen = true }
    func menuDidClose(_ menu: NSMenu) { isMenuOpen = false }

    /// Items that change while the timer runs. Updated every tick, but only while the menu is open.
    private func refreshLiveItems() {
        let phase = engine.phase
        let every = settings.longBreakEvery
        let header = phase == .focus
            ? "Focus · Session \(min(engine.completedInCycle + 1, every)) of \(every)"
            : phase.title
        let menuFontSize = NSFont.menuFont(ofSize: 0).pointSize
        headerItem.attributedTitle = NSAttributedString(string: header, attributes: [
            .font: NSFont.boldSystemFont(ofSize: menuFontSize),
            .foregroundColor: NSColor.labelColor,
        ])

        let detail: String
        switch engine.state {
        case .idle:
            detail = "Ready · \(settings.minutes(for: phase)) min"
            toggleItem.title = "Start \(phase.title)"
        case .running(let end):
            detail = "\(Format.clock(engine.remaining)) left · ends at \(Format.time(end))"
            toggleItem.title = "Pause"
        case .paused:
            detail = "Paused · \(Format.clock(engine.remaining)) left"
            toggleItem.title = "Resume"
        }
        detailItem.attributedTitle = NSAttributedString(string: detail, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: menuFontSize, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])

        resetItem.isEnabled = engine.state != .idle
        skipItem.title = "Skip to \(engine.nextPhase.title)"

        let today = settings.today
        statsItem.title = "Today: \(today.count) \(today.count == 1 ? "pomodoro" : "pomodoros") · \(Format.duration(today.focusSeconds)) focused"
    }

    /// Items that only change through the menu itself. Updated when the menu opens.
    private func refreshSettingsItems() {
        for (phase, parent) in durationItems {
            let current = settings.minutes(for: phase)
            parent.title = "\(phase.title): \(current) min"
            var matchedPreset = false
            for item in parent.submenu?.items ?? [] where !item.isSeparatorItem {
                if item.tag == 0 {
                    item.state = matchedPreset ? .off : .on
                    item.title = matchedPreset ? "Custom…" : "Custom (\(current) min)…"
                } else {
                    item.state = item.tag == current ? .on : .off
                    matchedPreset = matchedPreset || item.tag == current
                }
            }
        }

        let every = settings.longBreakEvery
        cycleItem.title = "Long Break After: \(every) Sessions"
        for item in cycleItem.submenu?.items ?? [] { item.state = item.tag == every ? .on : .off }

        autoBreaksItem.state = settings.autoStartBreaks ? .on : .off
        autoFocusItem.state = settings.autoStartFocus ? .on : .off
        soundItem.state = settings.playSound ? .on : .off
        showTimeItem.state = settings.showTimeInMenuBar ? .on : .off
        shortcutItem.state = settings.globalShortcut ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        toggleItem.keyEquivalent = settings.globalShortcut ? "p" : ""
    }

    // MARK: Timer actions

    @objc private func toggleTimer() { engine.toggle() }
    @objc private func resetTimer() { engine.reset() }
    @objc private func skipPhase() { engine.skip() }

    private func updateHotKey() {
        hotKey = settings.globalShortcut
            ? HotKey(keyCode: kVK_ANSI_P, modifiers: controlKey | optionKey) { [weak self] in
                // While the menu is open its own ⌃⌥P key equivalent handles the press.
                guard let self, !self.isMenuOpen else { return }
                self.engine.toggle()
            }
            : nil
    }

    // MARK: Settings actions

    @objc private func pickDuration(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let phase = Phase(rawValue: raw) else { return }
        var minutes = sender.tag
        if minutes == 0 {
            guard let custom = promptMinutes(for: phase) else { return }
            minutes = custom
        }
        settings.setMinutes(minutes, for: phase)
        render()
    }

    @objc private func pickCycleLength(_ sender: NSMenuItem) {
        settings.longBreakEvery = sender.tag
        render()
    }

    @objc private func toggleAutoBreaks() { settings.autoStartBreaks.toggle() }
    @objc private func toggleAutoFocus() { settings.autoStartFocus.toggle() }
    @objc private func toggleSound() { settings.playSound.toggle() }

    @objc private func toggleShowTime() {
        settings.showTimeInMenuBar.toggle()
        render()
    }

    @objc private func toggleShortcut() {
        settings.globalShortcut.toggle()
        updateHotKey()
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            showAlert("Couldn't change Launch at Login", error.localizedDescription)
        }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    // MARK: Dialogs

    private func promptMinutes(for phase: Phase) -> Int? {
        let alert = NSAlert()
        alert.messageText = "Custom \(phase.title) Length"
        alert.informativeText = "Enter a length in minutes (1–180)."
        let field = NSTextField(string: "\(settings.minutes(for: phase))")
        field.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Set")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        activateApp()

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        guard let value = Int(field.stringValue.trimmingCharacters(in: .whitespaces)), (1...180).contains(value) else {
            NSSound.beep()
            return nil
        }
        return value
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        activateApp()
        alert.runModal()
    }

    private func activateApp() {
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
