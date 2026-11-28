import AppKit
import SnapshotTesting
import SwiftUI
import XCTest

/// Route 1's guided week, Mon Nov 30 to Sun Dec 6: the calendar first, then projects, then practices.
@MainActor
final class FirstRunWeekTests: XCTestCase {
    private func week(_ plan: WeekPlan, selection: WeekSelection? = nil, practiceTip: WeekSelection? = nil) -> some View {
        FirstRunWeek(plan: plan, selection: selection, practiceTip: practiceTip).padding(.top, 28).background(Theme.background)
    }

    /// Getting started: every event plain, a tip on the first saying they can be told what they're for.
    func testWeekStart() {
        assertAppearances(week(Fixtures.weekStart), width: 1280, height: 820)
    }

    /// Before the calendar can be read: why, and Allow access.
    func testWeekCalendarAccess() {
        var plan = Fixtures.weekStart
        plan.events = []
        plan.calendar = .notAsked
        assertAppearances(week(plan), width: 1280, height: 820)
    }

    /// The product review asked about: a project or practice, time to fill, or just an event.
    func testWeekEventQuestion() {
        let review = Fixtures.weekEvents.first { $0.title == "Product review" }!
        assertAppearances(week(Fixtures.weekStart, selection: .event(review.key)), width: 1280, height: 820)
    }

    /// The product review as the pricing page's reserved time, its question still open.
    func testWeekEventLinked() {
        assertAppearances(week(Fixtures.weekAnswered(stage: .calendar), selection: .block("review")), width: 1280, height: 820)
    }

    /// The calendar answered, on to projects: Deep work faded to time to fill, the tip pointing at the plate.
    func testWeekProjects() {
        assertAppearances(week(Fixtures.weekAnswered()), width: 1280, height: 820)
    }

    /// The first project dropped: a session or reserved?
    func testWeekProjectDropped() {
        let plan = Fixtures.weekAnswered(blocks: [Fixtures.weekPricingSession])
        assertAppearances(week(plan, selection: .block(Fixtures.weekPricingSession.id)), width: 1280, height: 820)
    }

    /// The first practice dropped: how it counts.
    func testWeekPracticeDropped() {
        let plan = Fixtures.weekAnswered(stage: .practices, blocks: [Fixtures.weekPricingSession, Fixtures.weekSpanish])
        assertAppearances(week(plan, practiceTip: .block(Fixtures.weekSpanish.id)), width: 1280, height: 820)
    }

    /// The week planned: sessions, reserved time, practices counting, time to fill left.
    func testWeekPlanned() {
        assertAppearances(week(Fixtures.weekPlanned), width: 1280, height: 820)
    }

    /// Time drawn on Tuesday afternoon: what it’s for, the projects then the practices, each with the time it has.
    func testWeekTimeDrawn() {
        assertAppearances(
            FirstRunWeek(plan: Fixtures.weekAnswered(blocks: [Fixtures.weekPricingSession]), drawn: WeekDrawnTime(day: 1, start: 13 * 60, end: 14 * 60 + 30))
                .padding(.top, 20).background(Theme.background),
            width: 1280, height: 820
        )
    }
}
