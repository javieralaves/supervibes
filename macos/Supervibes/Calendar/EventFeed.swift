import AppKit
import EventKit
import Foundation
import Observation

/*
 * Calendar import's feed: the events in the person's Google calendars, read through macOS
 * Calendar with EventKit. Nothing here reaches the server until an event is imported. It reads
 * again when macOS says calendars changed (Google syncing in), when the app comes back to the
 * front, and on "sync now". All EventKit stays in this file; the rest of the app sees
 * ExternalEvent and ExternalCalendar (Shared/Models/EventImport.swift).
 */
@MainActor
@Observable
final class EventFeed {
    private(set) var settings = EventImportSettings.load()
    private(set) var access: CalendarAccess = .notAsked
    /// The Google calendars macOS Calendar has, by name.
    private(set) var calendars: [ExternalCalendar] = []
    /// Events in the ticked calendars over `range`, soonest first.
    private(set) var events: [ExternalEvent] = []
    /// When the events were last read.
    private(set) var lastRead: Date?

    /// The dates read: by default from five weeks back to six ahead, as the calendar loads blocks.
    @ObservationIgnored private var range: (start: Date, end: Date) = EventFeed.defaultRange(now: Date())
    @ObservationIgnored private let store = EKEventStore()

    init() {
        refreshAccess()
        reload()
        // Google syncing in, or the person changing something in Calendar.
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        // Coming back from System Settings, access may have been allowed or turned off.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let before = self.access
                self.refreshAccess()
                if self.access != before || self.access == .allowed { self.reload() }
            }
        }
    }

    /// Whether events are listed on the Calendar: on in Settings, and readable.
    var isActive: Bool { settings.isOn && access == .allowed }

    /// The ticked calendars.
    var includedCalendars: [ExternalCalendar] { calendars.filter(settings.includes) }

    // MARK: - Settings

    /// Asks macOS for access to calendars, the first time; afterwards only System Settings can change it.
    func requestAccess() {
        Task {
            do {
                let granted = try await store.requestFullAccessToEvents()
                Log.app.info("Calendar access \(granted ? "allowed" : "not allowed", privacy: .public)")
            } catch {
                Log.app.error("Calendar access: \(error.localizedDescription, privacy: .public)")
            }
            refreshAccess()
            reload()
        }
    }

    func change(_ new: EventImportSettings) {
        let reread = new.calendarIds != settings.calendarIds || new.hidesAllDay != settings.hidesAllDay || new.isOn != settings.isOn
        settings = new
        new.save()
        if reread { reload() }
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Reading

    /// The dates to read, as the calendar loads them.
    func setRange(start: Date, end: Date) {
        guard start != range.start || end != range.end else { return }
        range = (start, end)
        reload()
    }

    /// "Sync now": asks the accounts to sync, then reads what's here. What they bring in arrives
    /// with the store's change notification.
    func syncNow() {
        guard access == .allowed else { return }
        store.refreshSourcesIfNecessary()
        reload()
    }

    /// Whether a calendar is one whose events are read now: ticked, and still there. A block whose
    /// event is missing only counts as deleted when its calendar is.
    func isReading(calendarNamed name: String) -> Bool {
        isActive && includedCalendars.contains { $0.title == name }
    }

    private func refreshAccess() {
        access = switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .allowed
        case .notDetermined: .notAsked
        default: .denied
        }
    }

    private func reload() {
        guard access == .allowed else {
            calendars = []
            events = []
            return
        }
        let google = store.calendars(for: .event).filter { calendar in
            guard calendar.type == .calDAV, let source = calendar.source else { return false }
            return EventKey.isGoogleAccount(isCalDAV: source.sourceType == .calDAV, title: source.title)
        }
        calendars = google
            .map { ExternalCalendar(id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        let ticked = google.filter { settings.includes(ExternalCalendar(id: $0.calendarIdentifier, title: $0.title)) }
        guard settings.isOn, !ticked.isEmpty else {
            events = []
            lastRead = Date()
            return
        }
        let predicate = store.predicateForEvents(withStart: range.start, end: range.end, calendars: ticked)
        events = store.events(matching: predicate)
            .filter { $0.status != .canceled && !(settings.hidesAllDay && $0.isAllDay) }
            .compactMap(Self.event)
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
        lastRead = Date()
        Log.app.info("Calendar import: read \(self.events.count) events from \(ticked.count) calendars")
    }

    private static func event(_ event: EKEvent) -> ExternalEvent? {
        guard let externalId = event.calendarItemExternalIdentifier, let calendar = event.calendar else { return nil }
        let isOccurrence = event.hasRecurrenceRules || event.isDetached
        return ExternalEvent(
            key: EventKey.make(externalId: externalId, isOccurrence: isOccurrence, occurrenceDate: event.occurrenceDate),
            calendarId: calendar.calendarIdentifier,
            calendarName: calendar.title,
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            repeats: isOccurrence
        )
    }

    private static func defaultRange(now: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return (calendar.date(byAdding: .day, value: -36, to: today) ?? today, calendar.date(byAdding: .day, value: 43, to: today) ?? today)
    }
}
