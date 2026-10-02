import Foundation
import UserNotifications

private let startAction = "START"
private let startBreakCategory = "START_BREAK"
private let startFocusCategory = "START_FOCUS"

/// Posts phase-end notifications, with a one-click "Start" button when auto-start is off.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    var onStart: (@MainActor () -> Void)?

    func setUp() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(identifier: startBreakCategory,
                                   actions: [UNNotificationAction(identifier: startAction, title: "Start Break")],
                                   intentIdentifiers: []),
            UNNotificationCategory(identifier: startFocusCategory,
                                   actions: [UNNotificationAction(identifier: startAction, title: "Start Focus")],
                                   intentIdentifiers: []),
        ])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(finished: Phase, next: Phase, minutes: Int, autoStarted: Bool) {
        let content = UNMutableNotificationContent()
        if finished == .focus {
            content.title = "Focus session complete 🍅"
            content.body = autoStarted
                ? "\(next.title) started: \(minutes) min. Step away from the screen."
                : "Time for a \(next.title.lowercased()) (\(minutes) min)."
        } else {
            content.title = "Break's over"
            content.body = autoStarted
                ? "Focus started: \(minutes) min."
                : "Ready for another \(minutes)-minute focus session?"
        }
        if !autoStarted {
            content.categoryIdentifier = next == .focus ? startFocusCategory : startBreakCategory
        }
        // A fixed identifier makes each notification replace the last instead of piling up.
        let request = UNNotificationRequest(identifier: "phase-end", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let shouldStart = response.actionIdentifier == startAction
        completionHandler()
        guard shouldStart else { return }
        Task { @MainActor in self.onStart?() }
    }
}
