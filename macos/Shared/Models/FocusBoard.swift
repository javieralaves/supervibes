import Foundation

/*
 * Route 2, the next few months (the design's "Route 2 · The next few months"): up to three things from the plate to
 * focus on for a season, drawn as a board. Each focus becomes a quest holding that one project or practice. The rest
 * keeps going, or waits for next season: its practices are paused until the season ends, its projects kept on this
 * Mac. Several focuses can come from the same area.
 */

/// One thing on the plate, as made: a project or practice with the area it sits in.
struct FocusItem: Identifiable, Hashable, Codable, Sendable {
    /// The goal's id.
    let id: String
    var title: String
    var icon: String
    var color: String
    var isPractice: Bool
    var perWeek: Int?
    var areaId: String
    var areaName: String
    var areaIcon: String
    /// What sorting heard that helps pick: "Before Q1 planning", "In February, with Marta".
    var detail: String?

    /// "3 times a week", "Once a week".
    var rhythm: String? {
        perWeek.map { $0 == 1 ? "Once a week" : "\($0) times a week" }
    }

    var kindName: String { isPractice ? "Practice" : "Project" }

    /// Under its title on the plate: what helps pick it, or else its area and kind.
    var plateLine: String { detail ?? (isPractice ? rhythm : nil) ?? "\(areaName) · \(kindName)" }
}

/// The board: what's in focus, in order, and what waits for next season; everything else keeps going.
struct FocusBoard: Hashable, Codable, Sendable {
    static let slots = 3

    var items: [FocusItem]
    /// The focuses' goal ids, Focus 1 first.
    var focus: [String] = []
    var waiting: Set<String> = []
    /// Quest names, by goal id, as renamed on the season's cards; a focus not renamed keeps its title.
    var names: [String: String] = [:]

    func item(_ id: String) -> FocusItem? { items.first { $0.id == id } }

    var focused: [FocusItem] { focus.compactMap(item) }
    var keepGoing: [FocusItem] { items.filter { !focus.contains($0.id) && !waiting.contains($0.id) } }
    var waits: [FocusItem] { items.filter { waiting.contains($0.id) } }
    var isFull: Bool { focus.count >= Self.slots }

    /// Whether clicking it fills the next slot: not in focus, and a slot free.
    func canFocus(_ id: String) -> Bool { !focus.contains(id) && !isFull }

    /// Whether it can be dropped onto slot `slot` (0 first): onto an empty slot as clicking would, or onto a focus to
    /// swap it out.
    func canPlace(_ id: String, at slot: Int) -> Bool {
        guard item(id) != nil else { return false }
        if focus.contains(id) { return slot < focus.count }
        if slot >= focus.count { return canFocus(id) }
        return true
    }

    /// Into the next free slot.
    mutating func choose(_ id: String) {
        guard canFocus(id) else { return }
        waiting.remove(id)
        focus.append(id)
    }

    /// Dropped onto slot `slot`: an empty one fills the next free slot; a focus is swapped out, back to keep going,
    /// or, for one already in focus, the two trade places.
    mutating func place(_ id: String, at slot: Int) {
        guard canPlace(id, at: slot) else { return }
        if let from = focus.firstIndex(of: id) {
            focus.swapAt(from, slot)
        } else if slot < focus.count {
            waiting.remove(id)
            focus[slot] = id
        } else {
            choose(id)
        }
    }

    /// Out of focus, back to keep going, freeing its slot.
    mutating func remove(_ id: String) {
        focus.removeAll { $0 == id }
    }

    /// To wait for next season.
    mutating func wait(_ id: String) {
        guard item(id) != nil else { return }
        focus.removeAll { $0 == id }
        waiting.insert(id)
    }

    /// Back from waiting, to keep going.
    mutating func keep(_ id: String) {
        waiting.remove(id)
    }

    /// A focus's quest name: as renamed, or its title.
    func name(_ id: String) -> String {
        let name = names[id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? (item(id)?.title ?? "") : name
    }
}

/// The season Route 2 makes, by the dates the app shows: 13 weeks from next Monday.
struct SeasonSpan: Hashable, Codable, Sendable {
    var startsOn: Date
    var endsOn: Date

    init(endsOn: Date) {
        self.endsOn = endsOn
        startsOn = Calendar.current.date(byAdding: .day, value: -(13 * 7 - 1), to: endsOn) ?? endsOn
    }

    /// A season's own days, "YYYY-MM-DD", as local midnights.
    init(startsOn: String, endsOn: String) {
        let parse = { (day: String) -> Date? in
            let parts = day.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        }
        let end = parse(endsOn) ?? .now
        self.endsOn = end
        self.startsOn = parse(startsOn) ?? end
    }

    var weeks: Int { ((Calendar.current.dateComponents([.day], from: startsOn, to: endsOn).day ?? 90) + 1) / 7 }

    /// "Nov 30".
    static func day(_ date: Date) -> String { date.formatted(.dateTime.month(.abbreviated).day().locale(WeekPlan.locale)) }
    /// "February".
    var endMonth: String { endsOn.formatted(.dateTime.month(.wide).locale(WeekPlan.locale)) }
    /// "Nov 30 – Feb 28, 13 weeks".
    var label: String { "\(Self.day(startsOn)) – \(Self.day(endsOn)), \(weeks) weeks" }
}

/// A quest in the week of Route 2 or 3: its number, its name, and the projects and practices that move it.
struct WeekQuest: Identifiable, Hashable, Codable, Sendable {
    var id: Int { number }
    let number: Int
    let title: String
    /// What moves it, the first first: dragging the quest gives that one time.
    let goalIds: [String]

    init(number: Int, title: String, goalIds: [String]) {
        self.number = number
        self.title = title
        self.goalIds = goalIds
    }

    private enum CodingKeys: String, CodingKey { case number, title, goalIds, goalId }

    // Route 2's first build kept one goalId; read either.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        number = try c.decode(Int.self, forKey: .number)
        title = try c.decode(String.self, forKey: .title)
        goalIds = try c.decodeIfPresent([String].self, forKey: .goalIds) ?? [c.decode(String.self, forKey: .goalId)]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(number, forKey: .number)
        try c.encode(title, forKey: .title)
        try c.encode(goalIds, forKey: .goalIds)
    }
}

/// A badge on the plate: a project's or practice's icon and colour.
struct PlateBadge: Hashable, Sendable {
    let icon: String
    let color: String
    let isPractice: Bool
}

/// One quest card in the season's stack, for Route 2 or 3: its area and colour, what moves it, and, for a gap's
/// quest, how much of the gap the season would close.
struct SeasonCard: Identifiable, Hashable, Sendable {
    /// What renaming it is keyed by: the focus's goal in Route 2, the quest in Route 3.
    let id: String
    let number: Int
    let areaName: String
    let areaIcon: String
    let color: String
    /// What moves it first, set off along its track.
    let mover: PlateBadge
    /// "Run, 3 times a week".
    let movedBy: String
    /// Made while starting the season.
    var isNew = false
    /// For a gap's quest, 0–100 of the gap the season would close; nil draws Route 2's track, all the way.
    var reach: Int?
}

/// What else is on the plate, under the season's stack.
enum SeasonRest: Hashable, Sendable {
    /// Route 2: what still gets time, and what waits for next season.
    case split(keep: [PlateBadge], waits: [PlateBadge])
    /// Route 3: all of it keeps going.
    case keepsGoing([PlateBadge])
}

extension FocusItem {
    var badge: PlateBadge { PlateBadge(icon: icon, color: color, isPractice: isPractice) }
}

extension FocusBoard {
    /// The focuses as the season's cards.
    var seasonCards: [SeasonCard] {
        focused.enumerated().map { index, item in
            SeasonCard(
                id: item.id, number: index + 1, areaName: item.areaName, areaIcon: item.areaIcon, color: item.color,
                mover: item.badge,
                movedBy: item.isPractice ? "\(item.title), \((item.rhythm ?? "").lowercased())" : item.title
            )
        }
    }

    var seasonRest: SeasonRest { .split(keep: keepGoing.map(\.badge), waits: waits.map(\.badge)) }
}
