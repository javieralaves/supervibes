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

/// A block on the calendar this week or next, any goal's: for finding free time and giving time.
struct BoardBlock: Identifiable, Hashable, Sendable {
    let id: String
    let goalId: String
    var start: Date
    var end: Date
    /// Kept for its own sake: no room for tasks.
    var reserved = false
    /// The task it gives a time to, if any.
    var taskId: String?

    var minutes: Int { max(0, Int((end.timeIntervalSince(start) / 60).rounded())) }
    /// A session: time to work on its goal, not reserved and not a task's own time.
    var isSession: Bool { !reserved && taskId == nil }
}

struct BoardData: Hashable, Sendable {
    /// "YYYY-MM-DD".
    let today: String
    var clock: Clock?
    var goals: [BoardGoal]
    /// Every block this week and next, across goals, earliest first.
    var blocks: [BoardBlock] = []
    /// When the person's day starts and they go to sleep, in minutes after midnight (a sleep
    /// before the wake time falls after midnight).
    var wakeTime = 8 * 60
    var sleepStart = 23 * 60

    func goal(_ id: String) -> BoardGoal? { goals.first { $0.id == id } }
}

/// What the board shows: every goal, a row each, or one goal's lanes.
enum BoardScope: Hashable, Sendable {
    case all
    case goal(String)
}
