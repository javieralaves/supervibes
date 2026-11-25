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
