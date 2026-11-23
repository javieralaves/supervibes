import Foundation

/*
 * The planning board across goals, as GET /plan sends it (src/lib/api/routes/plan.ts): each goal's
 * open tasks, what it finished this week, its objective, and its session time this week and next.
 */

/// One goal on the board.
struct BoardGoal: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    /// A Hugeicons name from GoalPalette.
    var icon: String
    /// A key from GoalPalette.
    var color: String
    /// What this week should move for it.
    var objective: String?
    /// Open tasks, in order.
    var tasks: [TaskItem]
    /// Finished this week, most recently first.
    var done: [TaskItem]
    /// Its sessions this week and next (never reserved time).
    var protectedBlocks: [ProtectedBlock]
}

struct BoardData: Hashable, Sendable {
    /// "YYYY-MM-DD".
    let today: String
    var clock: Clock?
    var goals: [BoardGoal]

    func goal(_ id: String) -> BoardGoal? { goals.first { $0.id == id } }
}

/// What the board shows: every goal, a row each, or one goal's lanes.
enum BoardScope: Hashable, Sendable {
    case all
    case goal(String)
}
