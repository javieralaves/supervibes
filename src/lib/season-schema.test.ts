import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  defaultSeason,
  focusProblem,
  overlaps,
  popularAreasFor,
  questEffort,
  seasonInputSchema,
  seasonName,
  seasonStatus,
  seasonWeek,
  seasonWeeks,
  startProblem,
} from "./season-schema";

// Winter, as the design draws it: Monday, Nov 30, 2026 to Sunday, Feb 28, 2027.
const WINTER = { startsOn: "2026-11-30", endsOn: "2027-02-28" };

describe("defaultSeason", () => {
  it("starts on the next Monday and runs 13 weeks", () => {
    // Thursday, Nov 26, 2026.
    assert.deepEqual(defaultSeason("2026-11-26"), { name: "Winter", ...WINTER });
  });

  it("starts a week later when today is already a Monday", () => {
    assert.equal(defaultSeason("2026-11-30").startsOn, "2026-12-07");
  });

  it("follows a running season: the Monday after it ends", () => {
    assert.equal(defaultSeason("2027-02-28").startsOn, "2027-03-01");
    assert.equal(defaultSeason("2027-02-28").name, "Spring");
  });
});

describe("seasonName", () => {
  it("names a season for the month at its middle", () => {
    assert.equal(seasonName("2026-03-02", "2026-05-31"), "Spring");
    assert.equal(seasonName("2026-06-01", "2026-08-30"), "Summer");
    assert.equal(seasonName("2026-08-31", "2026-11-29"), "Autumn");
  });
});

describe("seasonWeek", () => {
  it("counts weeks from the first day", () => {
    assert.equal(seasonWeeks(WINTER.startsOn, WINTER.endsOn), 13);
    assert.equal(seasonWeek(WINTER.startsOn, WINTER.endsOn, "2026-11-30"), 1);
    assert.equal(seasonWeek(WINTER.startsOn, WINTER.endsOn, "2026-12-06"), 1);
    assert.equal(seasonWeek(WINTER.startsOn, WINTER.endsOn, "2026-12-07"), 2);
    assert.equal(seasonWeek(WINTER.startsOn, WINTER.endsOn, "2027-02-28"), 13);
  });

  it("is 0 before it starts and past the last week once it's over", () => {
    assert.equal(seasonWeek(WINTER.startsOn, WINTER.endsOn, "2026-11-29"), 0);
    assert.equal(seasonWeek(WINTER.startsOn, WINTER.endsOn, "2027-03-01"), 14);
  });
});

describe("overlaps", () => {
  it("counts a shared last and first day", () => {
    assert.equal(overlaps(WINTER, { startsOn: "2027-02-28", endsOn: "2027-05-30" }), true);
    assert.equal(overlaps(WINTER, { startsOn: "2027-03-01", endsOn: "2027-05-30" }), false);
    assert.equal(overlaps(WINTER, { startsOn: "2026-09-01", endsOn: "2026-11-29" }), false);
  });
});

describe("questEffort and seasonStatus", () => {
  it("is the worst status, ignoring goals with none", () => {
    assert.equal(questEffort(["on_track", "at_risk", null]), "at_risk");
    assert.equal(questEffort(["on_track", "off_track"]), "off_track");
    assert.equal(questEffort([null, undefined]), null);
    assert.equal(questEffort([]), null);
  });

  it("only shows unclear when nothing is clearer", () => {
    assert.equal(questEffort(["unclear", "on_track"]), "on_track");
    assert.equal(questEffort(["unclear"]), "unclear");
  });

  it("rolls quests up the same way", () => {
    assert.equal(seasonStatus(["at_risk", "on_track", null]), "at_risk");
    assert.equal(seasonStatus([null]), null);
  });
});

describe("startProblem", () => {
  it("wants one to three quests, each with a goal", () => {
    assert.equal(startProblem([]), "no_quests");
    assert.equal(startProblem([{ goalCount: 1 }, { goalCount: 2 }, { goalCount: 1 }]), null);
    assert.equal(startProblem([{ goalCount: 1 }, { goalCount: 1 }, { goalCount: 1 }, { goalCount: 1 }]), "too_many_quests");
    assert.equal(startProblem([{ goalCount: 1 }, { goalCount: 0 }]), "quest_without_goals");
  });
});

describe("seasonInputSchema", () => {
  it("takes a season that ends after it starts and runs under six months", () => {
    assert.equal(seasonInputSchema.safeParse({ name: "Winter", ...WINTER }).success, true);
    assert.equal(seasonInputSchema.safeParse({ name: "Winter", startsOn: "2027-02-28", endsOn: "2026-11-30" }).success, false);
    assert.equal(seasonInputSchema.safeParse({ name: "Long", startsOn: "2026-01-05", endsOn: "2026-12-31" }).success, false);
    assert.equal(seasonInputSchema.safeParse({ name: " ", ...WINTER }).success, false);
  });
});

describe("popularAreasFor", () => {
  it("leaves out the areas the person already has, by name", () => {
    const names = popularAreasFor(["Superfocus", "Capacity Labs", "health", "Relationships"]).map((a) => a.name);
    assert.deepEqual(names, ["Work", "Money", "Home", "Growth", "Play", "Mind", "Meaning"]);
  });
});

describe("focusProblem", () => {
  it("takes one to three focuses, from any areas, several from one if they like", () => {
    assert.equal(focusProblem([{ areaId: "work" }]), null);
    assert.equal(focusProblem([{ areaId: "work" }, { areaId: "home" }, { areaId: "health" }]), null);
    assert.equal(focusProblem([{ areaId: "work" }, { areaId: "work" }]), null);
  });

  it("names what's wrong", () => {
    assert.equal(focusProblem([]), "no_focus");
    assert.equal(focusProblem([{ areaId: "a" }, { areaId: "b" }, { areaId: "c" }, { areaId: "d" }]), "too_many_focus");
    assert.equal(focusProblem([{ areaId: "work" }, { areaId: null }]), "focus_without_area");
  });
});
