import XCTest

/// Changing what was sorted (SortedPlate's edits): nothing said is lost, a task always has a project, and an area's
/// bucket comes and goes with its one-offs. Plain logic, no snapshots.
final class PlateEditingTests: XCTestCase {
    private var plate: SortedPlate { Fixtures.sortedPlate }

    private func titles(_ plate: SortedPlate, in area: String) -> [String] {
        plate.areas.first { $0.id == area }?.items.map(\.title) ?? []
    }

    /// Spanish made a practice twice a week, and renamed.
    func testPracticeRhythmAndName() {
        var plate = plate
        plate.apply(SortedEdit(kind: .practice, title: "Spanish lessons", areaId: "growth", perWeek: 2), to: .item("spanish"))
        let spanish = plate.items.first { $0.id == "spanish" }
        XCTAssertEqual(spanish?.title, "Spanish lessons")
        XCTAssertEqual(spanish?.perWeek, 2)
        XCTAssertTrue(spanish?.isPractice == true)
    }

    /// A project moved to another area keeps its tasks.
    func testMoveKeepsTasks() {
        var plate = plate
        plate.apply(SortedEdit(kind: .project, title: "Hire a product designer", areaId: "growth"), to: .item("hire"))
        XCTAssertFalse(titles(plate, in: "work").contains("Hire a product designer"))
        XCTAssertEqual(plate.items.first { $0.id == "hire" }?.tasks, ["Set up 3 interviews"])
        XCTAssertTrue(titles(plate, in: "growth").contains("Hire a product designer"))
    }

    /// A project turned practice can't hold tasks: they go to its area's bucket, made for them.
    func testPracticeHandsTasksToBucket() {
        var plate = plate
        plate.apply(SortedEdit(kind: .practice, title: "Move flats by January", areaId: "home", perWeek: 1), to: .item("move"))
        let bucket = plate.areas.first { $0.id == "home" }?.items.first(where: \.isBucket)
        XCTAssertEqual(bucket?.title, "Around the house")
        XCTAssertEqual(bucket?.tasks, ["Call the bank about the mortgage"])
    }

    /// A task moved from under a project to nothing bigger, then made its own project; the bucket goes when empty.
    func testTaskToBucketAndBack() {
        var plate = plate
        plate.apply(SortedEdit(kind: .task, title: "Call the bank about the mortgage", areaId: "home",
                               under: SortedPlate.bucketTarget("home")), to: .task(itemId: "move", index: 0))
        XCTAssertEqual(plate.items.first { $0.id == "move" }?.tasks, [])
        let bucket = plate.areas.first { $0.id == "home" }!.items.first(where: \.isBucket)!
        XCTAssertEqual(bucket.tasks, ["Call the bank about the mortgage"])

        plate.apply(SortedEdit(kind: .project, title: "Remortgage", areaId: "home"), to: .task(itemId: bucket.id, index: 0))
        XCTAssertNil(plate.areas.first { $0.id == "home" }!.items.first(where: \.isBucket))
        XCTAssertTrue(titles(plate, in: "home").contains("Remortgage"))
    }

    /// A project made a task can't go under itself: it lands in its area's bucket, and so do its own tasks.
    func testProjectToTaskNeverUnderItself() {
        var plate = plate
        plate.apply(SortedEdit(kind: .task, title: "Move flats by January", areaId: "home", under: "move"), to: .item("move"))
        let bucket = plate.areas.first { $0.id == "home" }?.items.first(where: \.isBucket)
        XCTAssertEqual(bucket?.tasks, ["Move flats by January", "Call the bank about the mortgage"])
        XCTAssertFalse(plate.homes(in: "home", excluding: "move").contains { $0.id == "move" })
    }

    /// Adding: a project, a practice still to be given a rhythm, a task in the bucket, and a new area.
    func testAdding() {
        var plate = plate
        plate.add("Write the case study", kind: .project, to: "work")
        plate.add("Stretch", kind: .practice, to: "health")
        plate.add("Renew the passport", kind: .task, to: "play")
        let area = plate.addArea("Relationships", icon: "Agreement01Icon")
        XCTAssertTrue(titles(plate, in: "work").contains("Write the case study"))
        XCTAssertTrue(plate.needsRhythm.contains { $0.title == "Stretch" })
        XCTAssertEqual(plate.areas.first { $0.id == "play" }?.items.first(where: \.isBucket)?.tasks, ["Renew the passport"])
        XCTAssertEqual(plate.areas.last?.name, "Relationships")
        XCTAssertEqual(plate.addArea("relationships", icon: "Agreement01Icon"), area)
    }

    /// Removing a task, and a project with its tasks.
    func testRemoving() {
        var plate = plate
        plate.remove(.task(itemId: "hire", index: 0))
        XCTAssertEqual(plate.items.first { $0.id == "hire" }?.tasks, [])
        plate.remove(.item("taxes"))
        XCTAssertNil(plate.items.first { $0.id == "taxes" })
    }
}
