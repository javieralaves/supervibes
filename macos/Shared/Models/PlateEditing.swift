import Foundation

/*
 * First run between the plate and What matters (the design's "Questions and edits"): a few questions about what's
 * fuzzy on the plate before it's sorted, then changing anything that was sorted. A task always sits under a project;
 * one that belongs to nothing bigger goes in its area's bucket, a project named for the area.
 */

// MARK: - Questions before sorting

/// One question about the plate: the words it's about, as typed, and the likely answers.
struct PlateQuestion: Identifiable, Hashable, Sendable {
    struct Option: Hashable, Sendable {
        let title: String
        /// How it would land: "A task under Move flats by January".
        let line: String
        let kind: PlateKind
    }

    var id: String { quote }
    let quote: String
    let question: String
    let options: [Option]
}

/// What something on the plate can be.
enum PlateKind: String, CaseIterable, Hashable, Codable, Sendable {
    case project, practice, task

    var name: String {
        switch self {
        case .project: "Project"
        case .practice: "Practice"
        case .task: "Task"
        }
    }

    /// What it means, in a few words.
    var line: String {
        switch self {
        case .project: "Has a finish line"
        case .practice: "Kept up weekly"
        case .task: "A one-off"
        }
    }
}

/// The questions asked before sorting, which one's showing, and what's been answered.
struct PlateClarify: Hashable, Sendable {
    var questions: [PlateQuestion] = []
    /// Which question is on top.
    var current = 0
    /// The option picked for each question, by its quote.
    var picked: [String: Int] = [:]
    /// What they added in their own words, by quote.
    var more: [String: String] = [:]

    var question: PlateQuestion? { questions.indices.contains(current) ? questions[current] : nil }
    var isLast: Bool { current >= questions.count - 1 }

    /// The questions answered so far, set aside: each with its quote and what it settled.
    var answered: [(quote: String, answer: String)] {
        questions.prefix(current).compactMap { question in
            if let index = picked[question.quote], question.options.indices.contains(index) {
                return (question.quote, question.options[index].title)
            }
            let words = more[question.quote]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return words.isEmpty ? nil : (question.quote, words)
        }
    }
}

// MARK: - Changing what was sorted

/// What's being changed on Sorted: a project or practice, or a task under one.
enum SortedSelection: Hashable, Sendable {
    case item(String)
    case task(itemId: String, index: Int)
}

/// A change made in Sorted's editing card: what it is, its name, its area, and what its kind needs.
struct SortedEdit: Hashable, Sendable {
    var kind: PlateKind
    var title: String
    var areaId: String
    /// For a practice: times a week.
    var perWeek: Int?
    /// For a task: the project it goes under, or its area's bucket (`SortedPlate.bucketTarget`).
    var under: String?
    /// A project's or practice's look: its icon and colour. Nil for a task, which gets one if it becomes either.
    var icon: String?
    var color: String?
}

/// The usual parts of life, to add one that isn't on the plate (src/lib/season-schema.ts' POPULAR_AREAS).
struct UsualArea: Hashable, Sendable {
    let name: String
    let icon: String
    let line: String

    static let all = [
        UsualArea(name: "Health", icon: "FavouriteIcon", line: "Your body, energy and how you look after them"),
        UsualArea(name: "Relationships", icon: "Agreement01Icon", line: "The people close to you"),
        UsualArea(name: "Work", icon: "Briefcase01Icon", line: "What you do, and where it’s going"),
        UsualArea(name: "Money", icon: "Wallet01Icon", line: "Income, spending and saving"),
        UsualArea(name: "Home", icon: "Sofa01Icon", line: "Where you live"),
        UsualArea(name: "Growth", icon: "Mortarboard01Icon", line: "What you’re learning"),
        UsualArea(name: "Play", icon: "PartyIcon", line: "Rest, hobbies and fun"),
        UsualArea(name: "Mind", icon: "BrainIcon", line: "Calm, stress, sleep"),
        UsualArea(name: "Meaning", icon: "Leaf01Icon", line: "What matters to you"),
    ]
}

extension SortedPlate {
    /// The bucket a task can go in when it belongs to nothing bigger, made when it's first used.
    static func bucketTarget(_ areaId: String) -> String { "bucket:\(areaId)" }

    /// A bucket's name, for its area: never "Miscellaneous".
    static func bucketName(for area: String) -> String {
        switch area.lowercased() {
        case "home": "Around the house"
        case "money": "Paperwork"
        case "work": "Work admin"
        case "health": "Appointments"
        case "relationships", "people": "Plans and favours"
        case "growth": "Things to sort out"
        case "play": "Plans to make"
        default: "\(area) odds and ends"
        }
    }

    func area(of itemId: String) -> PlateArea? { areas.first { $0.items.contains { $0.id == itemId } } }
    func item(_ id: String) -> PlateItem? { items.first { $0.id == id } }

    /// The projects a task could go under, in an area: its projects (but the one becoming a task) and its bucket
    /// (made if needed), bucket last.
    func homes(in areaId: String, excluding: String? = nil) -> [(id: String, title: String)] {
        guard let area = areas.first(where: { $0.id == areaId }) else { return [] }
        let projects = area.items.filter { !$0.isPractice && !$0.isBucket && $0.id != excluding }.map { ($0.id, $0.title) }
        let bucket = area.items.first(where: \.isBucket).map { ($0.id, $0.title) }
            ?? (Self.bucketTarget(areaId), Self.bucketName(for: area.name))
        return projects + [bucket]
    }

    /// The editing card's starting point for what's selected.
    func edit(for selection: SortedSelection) -> SortedEdit? {
        switch selection {
        case .item(let id):
            guard let item = item(id), let area = area(of: id) else { return nil }
            return SortedEdit(kind: item.isPractice ? .practice : .project, title: item.title, areaId: area.id, perWeek: item.perWeek,
                              icon: item.icon, color: item.color)
        case .task(let itemId, let index):
            guard let item = item(itemId), item.tasks.indices.contains(index), let area = area(of: itemId) else { return nil }
            return SortedEdit(kind: .task, title: item.tasks[index], areaId: area.id, under: itemId)
        }
    }

    // MARK: Changes

    /// Applies an edit to what's selected: renaming it, moving it, or turning it into another kind. Nothing is lost:
    /// a project's tasks that can't stay with it go to its area's bucket.
    mutating func apply(_ edit: SortedEdit, to selection: SortedSelection) {
        let title = edit.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        switch selection {
        case .item(let id):
            guard var item = take(id) else { return }
            item.title = title
            if let icon = edit.icon { item.icon = icon }
            if let color = edit.color { item.color = color }
            switch edit.kind {
            case .project:
                item.kind = .project
                item.perWeek = nil
                insert(item, in: edit.areaId)
            case .practice:
                let tasks = item.tasks
                item.kind = .practice
                item.perWeek = edit.perWeek ?? item.perWeek
                item.targetDate = nil
                item.tasks = []
                item.bucket = nil
                insert(item, in: edit.areaId)
                for task in tasks { addTask(task, under: Self.bucketTarget(edit.areaId)) }
            case .task:
                // It can't go under itself; that means its area's bucket.
                let under = edit.under == id ? nil : edit.under
                addTask(title, under: under ?? Self.bucketTarget(edit.areaId))
                for task in item.tasks { addTask(task, under: Self.bucketTarget(edit.areaId)) }
            }
        case .task(let itemId, let index):
            guard removeTask(itemId: itemId, index: index) else { return }
            switch edit.kind {
            case .task:
                addTask(title, under: edit.under ?? Self.bucketTarget(edit.areaId))
            case .project, .practice:
                add(title, kind: edit.kind, perWeek: edit.perWeek, to: edit.areaId)
            }
        }
        dropEmpty()
    }

    /// Takes what's selected off the plate.
    mutating func remove(_ selection: SortedSelection) {
        switch selection {
        case .item(let id): _ = take(id)
        case .task(let itemId, let index): _ = removeTask(itemId: itemId, index: index)
        }
        dropEmpty()
    }

    /// Something missed, added to an area: a project or practice, or a task in the area's bucket.
    mutating func add(_ title: String, kind: PlateKind, perWeek: Int? = nil, to areaId: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let a = areas.firstIndex(where: { $0.id == areaId }) else { return }
        if kind == .task { return addTask(title, under: Self.bucketTarget(areaId)) }
        let look = QuestSuggestion(kind: kind == .practice ? .practice : .project, title: title, line: "", perWeek: perWeek)
        areas[a].items.append(PlateItem(
            id: "item-\(UUID().uuidString)", title: title, kind: kind == .practice ? .practice : .project, detail: nil,
            perWeek: kind == .practice ? perWeek : nil, targetDate: nil, icon: look.icon, color: look.color, tasks: []
        ))
    }

    /// Another part of life, empty, at the end; or the one already there with that name.
    @discardableResult
    mutating func addArea(_ name: String, icon: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if let existing = areas.first(where: { $0.name.lowercased() == name.lowercased() }) { return existing.id }
        let id = "area-\(UUID().uuidString)"
        areas.append(PlateArea(id: id, name: name, icon: icon, items: []))
        return id
    }

    // MARK: Helpers

    private mutating func take(_ id: String) -> PlateItem? {
        for a in areas.indices {
            if let i = areas[a].items.firstIndex(where: { $0.id == id }) { return areas[a].items.remove(at: i) }
        }
        return nil
    }

    private mutating func insert(_ item: PlateItem, in areaId: String) {
        guard let a = areas.firstIndex(where: { $0.id == areaId }) else { return }
        areas[a].items.append(item)
    }

    private mutating func removeTask(itemId: String, index: Int) -> Bool {
        for a in areas.indices {
            if let i = areas[a].items.firstIndex(where: { $0.id == itemId }), areas[a].items[i].tasks.indices.contains(index) {
                areas[a].items[i].tasks.remove(at: index)
                return true
            }
        }
        return false
    }

    /// A task under a project, or in an area's bucket, made the first time it's needed.
    private mutating func addTask(_ task: String, under target: String) {
        if target.hasPrefix("bucket:") {
            let areaId = String(target.dropFirst("bucket:".count))
            guard let a = areas.firstIndex(where: { $0.id == areaId }) else { return }
            if let b = areas[a].items.firstIndex(where: \.isBucket) {
                areas[a].items[b].tasks.append(task)
            } else {
                let name = Self.bucketName(for: areas[a].name)
                areas[a].items.append(PlateItem(
                    id: "item-\(UUID().uuidString)", title: name, kind: .project, detail: nil, perWeek: nil, targetDate: nil,
                    icon: areas[a].icon, color: "slate", tasks: [task], bucket: true
                ))
            }
            return
        }
        for a in areas.indices {
            if let i = areas[a].items.firstIndex(where: { $0.id == target }) {
                areas[a].items[i].tasks.append(task)
                return
            }
        }
    }

    /// A bucket with nothing left in it goes.
    private mutating func dropEmpty() {
        for a in areas.indices { areas[a].items.removeAll { $0.isBucket && $0.tasks.isEmpty } }
    }
}
