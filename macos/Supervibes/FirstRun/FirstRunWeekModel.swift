import Foundation
import Observation

/// Route 1's guided week, on the app's own pieces: the blocks and goals come from a CalendarModel (which also makes,
/// imports, switches and removes blocks), the events from the person's Google calendars through the app's EventFeed.
///
/// Saying an event is time for a project or practice imports each of its series' occurrences this week as that one's
/// blocks; time to fill is kept on this Mac, by series, as the app keeps its other calendar settings.
@MainActor
@Observable
final class FirstRunWeekModel {
    private(set) var stage: WeekPlan.Stage = .calendar
    private(set) var selection: WeekSelection?
    /// The first practice dropped, while its tip shows.
    private(set) var practiceTip: WeekSelection?
    private(set) var open: Set<String>

    /// Today, the week's first day.
    let start: Date
    /// Route 2's quests and what waits for next season; none in Route 1.
    let quests: [WeekQuest]
    let waiting: Set<String>
    let steps: [String]
    @ObservationIgnored let calendar: CalendarModel
    @ObservationIgnored private let feed: EventFeed
    @ObservationIgnored private var placedProject = false
    @ObservationIgnored private var placedPractice = false

    private static let openKey = "firstRun.openSeries"

    init(auth: AuthModel, feed: EventFeed, quests: [WeekQuest] = [], waiting: Set<String> = [], steps: [String] = FirstRunChoice.week.steps) {
        calendar = CalendarModel(auth: auth, span: .week)
        self.feed = feed
        self.quests = quests
        self.waiting = waiting
        self.steps = steps
        start = WeekPlan.weekToPlan(from: .now)
        open = Set(UserDefaults.standard.stringArray(forKey: Self.openKey) ?? [])
    }

    func start() async {
        await calendar.refresh()
        // With nothing booked (or no calendar to read), the guide starts at projects.
        if plan.calendar == .ready && plan.events.isEmpty { stage = .projects }
    }

    // MARK: What the week shows

    var plan: WeekPlan {
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        let blocks = calendar.data.blocks.filter { $0.startsAt >= start && $0.startsAt < end }
        let imported = Set(blocks.compactMap { $0.source?.key })
        let events = feed.isActive ? feed.events.filter { $0.start >= start && $0.start < end && !imported.contains($0.key) } : []
        var plan = WeekPlan(start: start, events: events, blocks: blocks, goals: calendar.data.goals)
        plan.now = calendar.now
        plan.open = open
        plan.stage = stage
        plan.quests = quests
        plan.waiting = waiting
        plan.steps = steps
        plan.calendar = switch feed.access {
        case .notAsked: .notAsked
        case .denied: .denied
        case .allowed: feed.settings.isOn ? .ready : .off
        }
        return plan
    }

    var actions: WeekActions {
        WeekActions(
            select: { [weak self] in self?.selection = $0 },
            link: { [weak self] key, goalId in self?.link(key, to: goalId) },
            setSeriesReserved: { [weak self] series, reserved in self?.setReserved(series: series, reserved) },
            markOpen: { [weak self] in self?.answer($0, open: true) },
            markPlain: { [weak self] in self?.answer($0, open: false) },
            drop: { [weak self] goalId, day, start in self?.drop(goalId, day: day, start: start) },
            create: { [weak self] day, start, end, goalId, title, kind in
                self?.create(day: day, start: start, end: end, goalId: goalId, title: title, kind: kind)
            },
            move: { [weak self] id, edge, minutes, days in
                self?.calendar.move(id, edge: edge, delta: minutes, days: days)
                self?.selection = nil
            },
            setReserved: { [weak self] id, reserved in self?.calendar.setReserved(id, reserved) },
            remove: { [weak self] id in
                self?.calendar.remove(id)
                self?.selection = nil
            },
            next: { [weak self] in self?.next() },
            allowCalendar: { [weak self] in self?.allowCalendar() }
        )
    }

    // MARK: The calendar's events

    /// The event's series, every occurrence this week, as time for a project or practice: imported as its blocks.
    /// One already given to another is moved over.
    private func link(_ key: String, to goalId: String) {
        let series = WeekPlan.series(key)
        removeImported(series: series, except: goalId)
        let occurrences = feed.events.filter { WeekPlan.series($0.key) == series && plan.dayIndex($0.start) != nil }
        for event in occurrences where calendar.importedBlock(event.key) == nil {
            calendar.importEvent(event, goalId: goalId, kind: .session)
        }
        setOpen(series, false)
        if let event = feed.events.first(where: { $0.key == key }) ?? occurrences.first {
            selection = .placed(goalId: goalId, startsAt: ImportCheck.blockTimes(event.start, event.end).start)
        }
    }

    private func setReserved(series: String, _ reserved: Bool) {
        for block in plan.blocks where block.source.map({ WeekPlan.series($0.key) }) == series && block.reserved != reserved {
            calendar.setReserved(block.id, reserved)
        }
    }

    /// The series as time to fill, or as just an event: either way, no longer any project's.
    private func answer(_ series: String, open isOpen: Bool) {
        removeImported(series: series, except: nil)
        setOpen(series, isOpen)
        if let event = feed.events.first(where: { WeekPlan.series($0.key) == series && plan.dayIndex($0.start) != nil }) {
            selection = .event(event.key)
        }
    }

    private func removeImported(series: String, except goalId: String?) {
        for block in plan.blocks where block.source.map({ WeekPlan.series($0.key) }) == series && block.goalId != goalId {
            calendar.remove(block.id)
        }
    }

    private func setOpen(_ series: String, _ isOpen: Bool) {
        if isOpen { open.insert(series) } else { open.remove(series) }
        UserDefaults.standard.set(Array(open), forKey: Self.openKey)
    }

    private func allowCalendar() {
        switch feed.access {
        case .notAsked: feed.requestAccess()
        case .denied: feed.openSystemSettings()
        case .allowed:
            var settings = feed.settings
            settings.isOn = true
            feed.change(settings)
        }
    }

    // MARK: Projects and practices

    /// A project or practice dropped on a day: a session there, two hours for a project and a practice's own length,
    /// until midnight at the latest. The first project's asks whether it's a session or reserved; the first practice's
    /// says how it counts.
    private func drop(_ goalId: String, day: Int, start: Int) {
        guard let goal = calendar.data.goals.first(where: { $0.id == goalId }) else { return }
        let length = goal.isPractice ? max(goal.minMinutes ?? 60, 30) : 120
        let end = min(start + length, CalendarDayMath.dayMinutes)
        let date = Calendar.current.date(byAdding: .day, value: day, to: self.start) ?? self.start
        let offset = CalendarDayMath.dayOffset(date, from: calendar.now)
        calendar.create(day: offset, start: start, end: max(end, start + 15), goalId: goalId, title: nil, kind: .session)
        let startsAt = date.addingTimeInterval(Double(start) * 60)
        if goal.isPractice {
            if !placedPractice {
                placedPractice = true
                practiceTip = .placed(goalId: goalId, startsAt: startsAt)
                selection = nil
                stage = max(stage, .practices)
            }
        } else if !placedProject {
            placedProject = true
            selection = .placed(goalId: goalId, startsAt: startsAt)
            stage = max(stage, .practices)
        }
    }

    /// Time drawn on a day and given to a project or practice in the new block's card, which already said session or
    /// reserved; the first practice's still says how it counts.
    private func create(day: Int, start: Int, end: Int, goalId: String, title: String?, kind: NewBlockKind) {
        guard let goal = calendar.data.goals.first(where: { $0.id == goalId }) else { return }
        let date = Calendar.current.date(byAdding: .day, value: day, to: self.start) ?? self.start
        let offset = CalendarDayMath.dayOffset(date, from: calendar.now)
        calendar.create(day: offset, start: start, end: max(end, start + 15), goalId: goalId, title: title, kind: kind)
        selection = nil
        if goal.isPractice {
            if !placedPractice {
                placedPractice = true
                practiceTip = .placed(goalId: goalId, startsAt: date.addingTimeInterval(Double(start) * 60))
                stage = max(stage, .practices)
            }
        } else if !placedProject {
            placedProject = true
            stage = max(stage, .practices)
        }
    }

    private func next() {
        if practiceTip != nil {
            practiceTip = nil
            stage = .done
            return
        }
        stage = WeekPlan.Stage(rawValue: stage.rawValue + 1) ?? .done
    }
}

extension WeekPlan.Stage: Comparable {
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}
