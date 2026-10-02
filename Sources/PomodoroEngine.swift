import Foundation

/// The timer state machine. Time is derived from an absolute end date rather than a
/// decrementing counter, so it stays accurate across sleep, App Nap and run-loop delays.
@MainActor
final class PomodoroEngine {
    enum State: Equatable {
        case idle
        case running(endsAt: Date)
        case paused(remaining: TimeInterval)
    }

    private(set) var phase: Phase = .focus
    private(set) var state: State = .idle
    /// Focus sessions finished in the current cycle; resets after a long break.
    private(set) var completedInCycle = 0

    /// Called whenever visible state may have changed (at most once per second while running).
    var onChange: (@MainActor () -> Void)?
    /// Called when a phase runs to completion (not when it is skipped).
    var onPhaseEnd: (@MainActor (_ finished: Phase, _ next: Phase, _ autoStarted: Bool) -> Void)?

    private let settings: Settings
    private var sessionLength: TimeInterval = 0
    private var timer: Timer?
    private var activity: NSObjectProtocol?

    init(settings: Settings) {
        self.settings = settings
    }

    // MARK: Derived state

    func duration(of phase: Phase) -> TimeInterval { TimeInterval(settings.minutes(for: phase) * 60) }

    var remaining: TimeInterval {
        switch state {
        case .idle: duration(of: phase)
        case .running(let end): max(0, end.timeIntervalSinceNow)
        case .paused(let remaining): remaining
        }
    }

    var fractionRemaining: Double {
        let total = state == .idle ? duration(of: phase) : sessionLength
        return total > 0 ? min(1, remaining / total) : 0
    }

    var isRunning: Bool { if case .running = state { true } else { false } }
    var isPaused: Bool { if case .paused = state { true } else { false } }

    var nextPhase: Phase {
        guard phase == .focus else { return .focus }
        return completedInCycle + 1 >= settings.longBreakEvery ? .longBreak : .shortBreak
    }

    // MARK: Controls

    func start() {
        switch state {
        case .running:
            return
        case .idle:
            sessionLength = duration(of: phase)
            run(for: sessionLength)
        case .paused(let remaining):
            run(for: remaining)
        }
    }

    func pause() {
        guard isRunning else { return }
        state = .paused(remaining: remaining)
        stopTicking()
        onChange?()
    }

    func toggle() { isRunning ? pause() : start() }

    func reset() {
        stopTicking()
        state = .idle
        onChange?()
    }

    func skip() { advance(completed: false) }

    /// Call after the Mac wakes: catch up immediately and re-align ticks to whole seconds.
    func resync() {
        guard isRunning else { return }
        scheduleTicks()
        tick()
    }

    // MARK: Internals

    private func run(for seconds: TimeInterval) {
        state = .running(endsAt: Date().addingTimeInterval(seconds))
        scheduleTicks()
        onChange?()
    }

    private func advance(completed: Bool) {
        let finished = phase
        let next = nextPhase
        switch finished {
        case .focus:
            completedInCycle += 1
            if completed { settings.recordFocusSession(seconds: Int(sessionLength)) }
        case .longBreak:
            completedInCycle = 0
        case .shortBreak:
            break
        }

        stopTicking()
        phase = next
        state = .idle

        let autoStart = completed && (next == .focus ? settings.autoStartFocus : settings.autoStartBreaks)
        if autoStart { start() } else { onChange?() }
        if completed { onPhaseEnd?(finished, next, autoStart) }
    }

    private func scheduleTicks() {
        timer?.invalidate()
        guard case .running(let end) = state else { return }

        // First fire lands exactly when the displayed second changes; then once per second.
        let remaining = end.timeIntervalSinceNow
        var offset = remaining - remaining.rounded(.down)
        if offset < 0.01 { offset += 1 }

        let timer = Timer(fire: Date().addingTimeInterval(offset), interval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common) // .common keeps it ticking while the menu is open
        self.timer = timer

        if activity == nil {
            // Stop App Nap from throttling the 1 Hz tick. Idle system sleep is still allowed.
            activity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep, reason: "Pomodoro timer running")
        }
    }

    private func stopTicking() {
        timer?.invalidate()
        timer = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    private func tick() {
        guard case .running(let end) = state else { return }
        if end.timeIntervalSinceNow <= 0.05 {
            advance(completed: true)
        } else {
            onChange?()
        }
    }
}
