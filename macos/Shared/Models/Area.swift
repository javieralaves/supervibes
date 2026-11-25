import Foundation

/// A part of someone's life their goals sit in (src/lib/areas.ts), as Life and the area's page show it.
struct Area: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    /// A Hugeicons name from GoalPalette: areas share the goals' icons, drawn without a colour.
    var icon: String
    /// Where the person is in this area, in their words; nil until said.
    var now: String?
    /// Where they want it to go, in their words; nil until said.
    var want: String?
    /// Its goals' statuses rolled up: the worst of them. Nil with no goals, or none with a status yet.
    var status: GoalStatus?
    /// Its goals, in the goals' order.
    var goalIds: [String]
}

/// A goal's area as its page shows it: enough to name it and link to it.
struct AreaRef: Hashable, Sendable {
    let id: String
    let name: String
    let icon: String
}

/// One day of an area's last weeks: the worst of its goals' statuses that day.
struct AreaTrajectoryDay: Hashable, Sendable {
    /// "YYYY-MM-DD", in the person's own calendar.
    let day: String
    let status: GoalStatus?
    /// No goal in the area had a read that day.
    let carried: Bool
}

/// An area's page (AreaDetail in src/lib/api/routes/areas.ts).
struct AreaDetail: Hashable, Sendable {
    var area: Area
    let today: String
    /// The last 28 days, oldest first.
    let trajectory: [AreaTrajectoryDay]
    /// Its goals, as Life has them.
    var goals: [Goal]
    /// Each of its goals' week, by goal id.
    var weeks: [String: GoalWeek]
}

/// An area's status in words. Areas have no basis of their own, so they read as a goal with a target would:
/// "On track", "At risk", "Off track", or "Too early to tell".
func areaStatusLabel(_ status: GoalStatus) -> String {
    statusLabel(status, .target)
}

/// An area as the person edits it, whole (AreaInput in src/lib/area-schema.ts): a name and an icon, and optionally
/// where they are and where they're going. Blank words are sent as none.
struct AreaInput: Hashable, Sendable {
    var name = ""
    var icon = AreaInput.defaultIcon
    var now = ""
    var want = ""

    static let maxName = 40
    static let maxWords = 600
    /// What a new area starts with until an icon is picked.
    static let defaultIcon = "Target02Icon"

    init(name: String = "", icon: String = AreaInput.defaultIcon, now: String = "", want: String = "") {
        self.name = name
        self.icon = icon
        self.now = now
        self.want = want
    }

    /// An area as it is, for editing.
    init(editing area: Area) {
        self.init(name: area.name, icon: area.icon, now: area.now ?? "", want: area.want ?? "")
    }

    /// The server's checks, with its messages, so they show before anything is sent.
    var problem: String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Give the area a name." }
        if name.count > Self.maxName { return "Keep the name under \(Self.maxName) characters." }
        if now.trimmingCharacters(in: .whitespacesAndNewlines).count > Self.maxWords {
            return "Keep where you are under \(Self.maxWords) characters."
        }
        if want.trimmingCharacters(in: .whitespacesAndNewlines).count > Self.maxWords {
            return "Keep where you’re going under \(Self.maxWords) characters."
        }
        return nil
    }

    /// The area with these edits, as it shows before the server answers.
    func applied(to area: Area) -> Area {
        var edited = area
        edited.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        edited.icon = icon
        edited.now = now.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : now
        edited.want = want.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : want
        return edited
    }
}
