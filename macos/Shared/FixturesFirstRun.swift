import Foundation

/// First run as Alex goes through it on Thursday, Nov 26, 2026: the plate from the First run page in
/// supervibes-design, sorted as the server sorted it.
extension Fixtures {
    static let plateText = """
    pricing page launch, needs to ship before Q1 planning
    hiring a product designer, still have to set up 3 interviews
    moving flats by january?? haven’t found one yet
    also call the bank about the mortgage
    taxes, the accountant wants the papers
    running again, 3x a week ideally
    keep up spanish
    finally start that newsletter
    plan lisbon with marta for february
    """

    private static func item(
        _ id: String, _ title: String, _ kind: PlateItem.Kind, icon: String, color: String,
        detail: String? = nil, perWeek: Int? = nil, tasks: [String] = []
    ) -> PlateItem {
        PlateItem(id: id, title: title, kind: kind, detail: detail, perWeek: perWeek, targetDate: nil, icon: icon, color: color, tasks: tasks)
    }

    static let sortedPlate = SortedPlate(areas: [
        PlateArea(id: "work", name: "Work", icon: "Briefcase01Icon", items: [
            item("pricing", "Ship the new pricing page", .project, icon: "Rocket01Icon", color: "violet", detail: "Before Q1 planning"),
            item("hire", "Hire a product designer", .project, icon: "UserGroupIcon", color: "sky", tasks: ["Set up 3 interviews"]),
        ]),
        PlateArea(id: "home", name: "Home", icon: "Home01Icon", items: [
            item("move", "Move flats by January", .project, icon: "Sofa01Icon", color: "amber", detail: "By January",
                 tasks: ["Call the bank about the mortgage"]),
        ]),
        PlateArea(id: "money", name: "Money", icon: "Wallet01Icon", items: [
            item("taxes", "Sort out this year’s taxes", .project, icon: "Money03Icon", color: "slate", tasks: ["Get the papers to the accountant"]),
        ]),
        PlateArea(id: "health", name: "Health", icon: "FavouriteIcon", items: [
            item("run", "Run", .practice, icon: "RunningShoesIcon", color: "green", perWeek: 3),
        ]),
        PlateArea(id: "growth", name: "Growth", icon: "Mortarboard01Icon", items: [
            item("spanish", "Spanish", .practice, icon: "LanguageSkillIcon", color: "indigo"),
            item("newsletter", "Start a newsletter", .project, icon: "PenTool01Icon", color: "pink"),
        ]),
        PlateArea(id: "play", name: "Play", icon: "PartyIcon", items: [
            item("lisbon", "Plan the Lisbon trip", .project, icon: "Airplane01Icon", color: "teal", detail: "In February, with Marta"),
        ]),
    ])

    /// Three things: a light plate.
    static let lightPlate = SortedPlate(areas: [
        PlateArea(id: "work", name: "Work", icon: "Briefcase01Icon", items: [
            item("pricing", "Ship the new pricing page", .project, icon: "Rocket01Icon", color: "violet", detail: "Before Q1 planning"),
        ]),
        PlateArea(id: "health", name: "Health", icon: "FavouriteIcon", items: [
            item("run", "Run", .practice, icon: "RunningShoesIcon", color: "green", perWeek: 3),
        ]),
        PlateArea(id: "play", name: "Play", icon: "PartyIcon", items: [
            item("lisbon", "Plan the Lisbon trip", .project, icon: "Airplane01Icon", color: "teal", detail: "In February, with Marta"),
        ]),
    ])

    /// Sunday, Feb 28, 2027: the end of a 13-week season starting Monday, Nov 30.
    static let seasonEnd = Date(timeIntervalSince1970: 1_803_812_400)

    static func firstRun(_ step: FirstRunStep, plate: SortedPlate? = sortedPlate, text: String = plateText) -> FirstRunState {
        FirstRunState(step: step, firstName: "Alex", plateText: text, sorted: plate, seasonEnd: seasonEnd)
    }
}
