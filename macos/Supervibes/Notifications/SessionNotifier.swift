import AppKit
import Foundation
import Observation
import UserNotifications

/*
 * Sends the notices before sessions that the person picked in Settings (Shared/Models/
 * SessionNotices.swift). They're scheduled with the system from today's blocks, so they go out on
 * time even if the app has quit, and scheduled again whenever the blocks or the choice change.
 * Clicking one opens the calendar on that block.
 */
@MainActor
@Observable
final class SessionNotifier: NSObject {
    private(set) var settings = NoticeSettings.load()
    private(set) var permission: NoticePermission = .notAsked
    /// Clicking a notice: the block it's about.
    @ObservationIgnored var onOpenBlock: (String) -> Void = { _ in }

    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    @ObservationIgnored private var blocks: [Block] = []
    /// What's handed to the system, or nil before the first time this run.
    @ObservationIgnored private var scheduled: [SessionNotice]?
    /// Shown notices already taken out of Notification Center.
    @ObservationIgnored private var cleared: Set<String> = []

    override init() {
        super.init()
        // Set before launch finishes, so clicking a notice that launched the app still opens it.
        center.delegate = self
        Task { await refreshPermission() }
        // Coming back from System Settings, notifications may have been allowed or turned off.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.refreshPermission() }
            }
        }
    }

    /// The person changed the choice in Settings. Turning notices on asks macOS the first time.
    func change(_ new: NoticeSettings) {
        let turningOn = new.isOn && !settings.isOn
        settings = new
        new.save()
        Log.notices.info("Notices \(new.isOn ? "on" : "off", privacy: .public): \(new.active.map(\.minutes), privacy: .public)")
        if turningOn, permission == .notAsked {
            Task { await requestPermission() }
        }
        reschedule()
    }

    /// Today's blocks, as the app last fetched them.
    func blocksChanged(_ blocks: [Block]) {
        self.blocks = blocks
        reschedule()
    }

    /// Takes notices that are out of date out of Notification Center. Called on the app's clock.
    func tick(now: Date) {
        let outdated = Set(SessionNotices.outdated(for: blocks, leads: settings.active, now: now)).subtracting(cleared)
        guard !outdated.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: Array(outdated))
        cleared.formUnion(outdated)
    }

    func openSystemSettings() {
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleId)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: -

    private func reschedule() {
        let now = Date()
        let wanted = permission == .allowed ? SessionNotices.upcoming(for: blocks, leads: settings.active, now: now) : []
        // Ones that have gone out since aren't pending anymore; only what's still to come counts.
        if let scheduled, scheduled.filter({ $0.fireDate > now }) == wanted { return }

        if let scheduled {
            center.removePendingNotificationRequests(withIdentifiers: scheduled.map(\.id))
        } else {
            // First time this run: whatever an earlier run left may be out of date. Every request
            // the app schedules is a session notice.
            center.removeAllPendingNotificationRequests()
        }
        for notice in wanted {
            center.add(Self.request(for: notice)) { error in
                if let error {
                    Log.notices.error("Couldn't schedule \(notice.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        scheduled = wanted
        Log.notices.info("Scheduled \(wanted.count) notices")
    }

    private static func request(for notice: SessionNotice) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.subtitle = notice.subtitle
        content.body = notice.body
        content.sound = .default
        // Grouped by session in Notification Center.
        content.threadIdentifier = notice.blockId
        content.userInfo = ["blockId": notice.blockId]
        let when = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: notice.fireDate)
        return UNNotificationRequest(
            identifier: notice.id,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
        )
    }

    private func refreshPermission() async {
        let status = await withCheckedContinuation { (done: CheckedContinuation<UNAuthorizationStatus, Never>) in
            center.getNotificationSettings { done.resume(returning: $0.authorizationStatus) }
        }
        let new: NoticePermission = switch status {
        case .notDetermined: .notAsked
        case .denied: .denied
        default: .allowed
        }
        guard new != permission else { return }
        permission = new
        Log.notices.info("Permission: \(String(describing: new), privacy: .public)")
        reschedule()
    }

    private func requestPermission() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            Log.notices.error("Asking for permission: \(error.localizedDescription, privacy: .public)")
        }
        await refreshPermission()
    }
}

extension SessionNotifier: UNUserNotificationCenterDelegate {
    /// Shown even while Supervibes is the app in front.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let blockId = response.notification.request.content.userInfo["blockId"] as? String else { return }
        await MainActor.run { self.onOpenBlock(blockId) }
    }
}
