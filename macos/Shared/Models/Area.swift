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
    /// What stands between where it is and where they want it; nil until named or written.
    var gap: AreaGap? = nil
    /// Its quest in the running season, if it has one.
    var questId: String? = nil
}

/// The gap between where an area is and where the person wants it (src/lib/seasons.ts): a headline and a line or
/// two on what closing it takes. One per area; Supervibes names it when asked, or the person writes it.
struct AreaGap: Hashable, Sendable {
    enum Author: String, Sendable { case supervibes, you }

    var title: String
    /// May be empty.
    var body: String
    var by: Author
    /// When it was last named or written.
    var at: Date
}

/// A gap as the person writes it (gapSchema in src/lib/season-schema.ts).
struct GapInput: Hashable, Sendable {
    var title = ""
    var body = ""

    static let maxTitle = 160
    static let maxBody = 600

    init(title: String = "", body: String = "") {
        self.title = title
        self.body = body
    }

    /// A gap as it is, for editing.
    init(editing gap: AreaGap?) {
        self.init(title: gap?.title ?? "", body: gap?.body ?? "")
    }

    /// The server's checks, with its messages, so they show before anything is sent.
    var problem: String? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return "Name the gap in a few words." }
        if title.count > Self.maxTitle { return "Keep it under \(Self.maxTitle) characters." }
        if body.trimmingCharacters(in: .whitespacesAndNewlines).count > Self.maxBody {
            return "Keep it under \(Self.maxBody) characters."
        }
        return nil
    }
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
    /// Its latest read; nil until the person asks for one.
    var read: AreaRead? = nil
    /// Its quest in the running season, and that season; nil without one.
    var quest: Quest? = nil
    var season: Season? = nil
}

/// An area's read (src/lib/area-read.ts): a few lines on how it's going, from its goals' reads and the calendar.
/// Words only: the area's status stays its goals' worst.
struct AreaRead: Hashable, Sendable {
    let headline: String
    let summary: String
    /// The goals whose reads it drew on.
    let goalIds: [String]
    /// It drew on the person's time on the calendar.
    let usedCalendar: Bool
    let createdAt: Date
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
            return "Keep where you want to be under \(Self.maxWords) characters."
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
