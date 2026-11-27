import Foundation

/*
 * Route 2, the next few months (the design's "Route 2 · The next few months"): up to three things from the plate to
 * focus on for a season, drawn as a board. Each focus becomes a quest holding that one project or practice. The rest
 * keeps going, or waits for next season: its practices are paused until the season ends, its projects kept on this
 * Mac. A season has one quest an area, so it's one focus an area.
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

    /// The focus already taken in an item's area, if it's another thing.
    func areaFocus(for id: String) -> FocusItem? {
        guard let it = item(id) else { return nil }
        return focused.first { $0.areaId == it.areaId && $0.id != id }
    }

    /// Whether clicking it fills the next slot: not in focus, a slot free, and nothing else in focus from its area.
    func canFocus(_ id: String) -> Bool { !focus.contains(id) && !isFull && areaFocus(for: id) == nil }

    /// Whether it can be dropped onto slot `slot` (0 first): onto an empty slot as clicking would, or onto a focus to
    /// swap it out, as long as no other focus is in its area.
    func canPlace(_ id: String, at slot: Int) -> Bool {
        guard item(id) != nil else { return false }
        if focus.contains(id) { return slot < focus.count }
        if slot >= focus.count { return canFocus(id) }
        guard let taken = areaFocus(for: id) else { return true }
        return taken.id == focus[slot]
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

    var weeks: Int { ((Calendar.current.dateComponents([.day], from: startsOn, to: endsOn).day ?? 90) + 1) / 7 }

    /// "Nov 30".
    static func day(_ date: Date) -> String { date.formatted(.dateTime.month(.abbreviated).day().locale(WeekPlan.locale)) }
    /// "February".
    var endMonth: String { endsOn.formatted(.dateTime.month(.wide).locale(WeekPlan.locale)) }
    /// "Nov 30 – Feb 28, 13 weeks".
    var label: String { "\(Self.day(startsOn)) – \(Self.day(endsOn)), \(weeks) weeks" }
}

/// A quest in Route 2's week: its number, its name, and the one project or practice that moves it.
struct WeekQuest: Identifiable, Hashable, Codable, Sendable {
    var id: String { goalId }
    let number: Int
    let title: String
    let goalId: String
}
