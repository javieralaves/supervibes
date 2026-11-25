import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  countWeek,
  practiceState,
  practiceTrajectory,
  statusBefore,
  type Inputs,
  type PracticeBlock,
} from "./practice-count";

// Wednesday, Nov 25, 2026. Its week starts Monday, Nov 23.
const TODAY = "2026-11-25";

let next = 0;
const block = (day: string, extra: Partial<PracticeBlock> = {}): PracticeBlock => ({
  id: `b${next++}`,
  day,
  minutes: 30,
  ended: day < TODAY,
  missed: false,
  ...extra,
});

/** Three a week, made long ago, with `done` sessions in each of the weeks starting on these Mondays. */
function inputs(weeks: Record<string, number>, extra: Partial<Inputs> = {}): Inputs {
  const blocks = Object.entries(weeks).flatMap(([monday, done]) => Array.from({ length: done }, () => block(monday)));
  return {
    rhythm: { perWeek: 3, minMinutes: null, createdOn: "2026-01-01" },
    blocks,
    sessions: [],
    pauses: [],
    today: TODAY,
    ...extra,
  };
}

describe("countWeek", () => {
  it("counts blocks that have ended and ones done off the calendar, each on its own", () => {
    const week = countWeek(
      {
        ...inputs({}),
        blocks: [block("2026-11-23"), block("2026-11-23"), block("2026-11-27", { ended: false })],
        sessions: [
          { id: "s1", day: "2026-11-24", done: true },
          { id: "s2", day: "2026-11-26", done: false },
          { id: "s3", day: "2026-11-24", done: false },
        ],
      },
      "2026-11-23",
    );
    // Two blocks on Monday and Tuesday's logged one; Friday's block and Thursday's day are still to come. Tuesday's
    // unticked day has lapsed.
    assert.equal(week.done, 3);
    assert.equal(week.planned, 2);
  });

  it("leaves out blocks that didn't happen or are under the minimum", () => {
    const week = countWeek(
      {
        ...inputs({}, { rhythm: { perWeek: 3, minMinutes: 30, createdOn: "2026-01-01" } }),
        blocks: [block("2026-11-23", { missed: true }), block("2026-11-24", { minutes: 20 }), block("2026-11-24", { minutes: 30 })],
      },
      "2026-11-23",
    );
    assert.equal(week.done, 1);
  });
});

describe("statusBefore", () => {
  it("looks at the last four full weeks: 8 of 12 is at risk", () => {
    const status = statusBefore(inputs({ "2026-10-26": 3, "2026-11-02": 1, "2026-11-09": 2, "2026-11-16": 2 }), "2026-11-23");
    assert.deepEqual(status, { status: "at_risk", done: 8, expected: 12, weeks: 4 });
  });

  it("never lets a busy week make up for a missed one", () => {
    const status = statusBefore(inputs({ "2026-10-26": 6, "2026-11-02": 0, "2026-11-09": 3, "2026-11-16": 3 }), "2026-11-23");
    assert.equal(status?.done, 9);
    assert.equal(status?.status, "on_track");
  });

  it("is off track under half", () => {
    const status = statusBefore(inputs({ "2026-11-16": 1 }), "2026-11-23");
    assert.equal(status?.status, "off_track");
  });

  it("skips paused weeks and looks further back instead", () => {
    const status = statusBefore(
      inputs(
        { "2026-10-19": 3, "2026-10-26": 3, "2026-11-02": 3, "2026-11-16": 3 },
        { pauses: [{ startsOn: "2026-11-12", resumesOn: "2026-11-16" }] },
      ),
      "2026-11-23",
    );
    // The week of Nov 9 was paused from Thursday: left out, so Oct 19 counts in its place.
    assert.deepEqual(status, { status: "on_track", done: 12, expected: 12, weeks: 4 });
  });

  it("only counts weeks that started after it was made", () => {
    const status = statusBefore(
      inputs({ "2026-11-09": 0, "2026-11-16": 3 }, { rhythm: { perWeek: 3, minMinutes: null, createdOn: "2026-11-11" } }),
      "2026-11-23",
    );
    assert.deepEqual(status, { status: "on_track", done: 3, expected: 3, weeks: 1 });
  });

  it("has no status before its first full week", () => {
    assert.equal(statusBefore(inputs({}, { rhythm: { perWeek: 3, minMinutes: null, createdOn: "2026-11-18" } }), "2026-11-23"), null);
  });
});

describe("practiceState", () => {
  it("says what's done and left this week, without counting it against the status", () => {
    const state = practiceState(inputs({ "2026-11-09": 3, "2026-11-16": 3, "2026-11-23": 1 }));
    assert.equal(state.week.start, "2026-11-23");
    assert.equal(state.week.done, 1);
    assert.equal(state.week.left, 2);
    // Two full weeks, then two empty ones before them: 6 of 12.
    assert.equal(state.status?.status, "at_risk");
    assert.equal(state.weeks.length, 8);
    assert.equal(state.weeks.at(-1)?.start, "2026-11-16");
  });

  it("has no status while paused", () => {
    const state = practiceState(inputs({ "2026-11-16": 3 }, { pauses: [{ startsOn: "2026-11-24", resumesOn: "2026-12-07" }] }));
    assert.equal(state.status, null);
    assert.deepEqual(state.paused, { startsOn: "2026-11-24", resumesOn: "2026-12-07" });
  });
});

describe("practiceTrajectory", () => {
  it("gives each day its week's status, and none on paused days", () => {
    const days = practiceTrajectory(
      inputs(
        { "2026-11-09": 3, "2026-11-16": 0 },
        { rhythm: { perWeek: 3, minMinutes: null, createdOn: "2026-11-03" }, pauses: [{ startsOn: "2026-11-25", resumesOn: null }] },
      ),
      10,
    );
    assert.equal(days.length, 10);
    assert.equal(days[0].day, "2026-11-16");
    // The week of Nov 16 looks back at Nov 9, its only full week: on track. The week of Nov 23 sees Nov 16's miss too.
    assert.equal(days[0].status, "on_track");
    assert.equal(days.find((d) => d.day === "2026-11-23")?.status, "at_risk");
    assert.equal(days.find((d) => d.day === "2026-11-23")?.reason, "3 of the last 6");
    assert.equal(days.at(-1)?.status, null);
  });
});
