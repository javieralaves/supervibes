import Foundation

/// The area calls Life, an area's page and a goal's page share: list, add, edit and remove areas, and place a goal
/// in one. Each throws `AreaAPIError` with a message written for people, ready to show.
@MainActor
struct AreaAPI {
    let client: Client
    let auth: AuthModel

    func list() async throws -> [Area] {
        switch try await call({ try await client.listAreas(query: .init(timeZone: TimeZone.current.identifier)) }) {
        case .ok(let ok): return try ok.body.json.areas.map(Area.init(api:))
        case .unauthorized: throw await signedOut()
        case .badRequest(let bad): throw AreaAPIError((try? bad.body.json.error.message) ?? "Couldn’t load your areas.")
        case .undocumented(let status, _): throw AreaAPIError("Couldn’t load your areas (the server answered \(status)).")
        }
    }

    func create(_ input: AreaInput) async throws -> Area {
        switch try await call({ try await client.createArea(body: .json(body(input))) }) {
        case .created(let created): return Area(api: try created.body.json)
        case .unauthorized: throw await signedOut()
        case .badRequest(let bad): throw AreaAPIError((try? bad.body.json.error.message) ?? "Couldn’t add that area.")
        case .undocumented(let status, _): throw AreaAPIError("Couldn’t add that area (the server answered \(status)).")
        }
    }

    func update(_ id: String, _ input: AreaInput) async throws -> Area {
        switch try await call({ try await client.updateArea(path: .init(id: id), body: .json(body(input))) }) {
        case .ok(let ok): return Area(api: try ok.body.json)
        case .unauthorized: throw await signedOut()
        case .notFound: throw AreaAPIError("That area doesn’t exist anymore.")
        case .badRequest(let bad): throw AreaAPIError((try? bad.body.json.error.message) ?? "Couldn’t save that area.")
        case .undocumented(let status, _): throw AreaAPIError("Couldn’t save that area (the server answered \(status)).")
        }
    }

    /// Removes an area. Its goals stay, with no area. Gone already counts as done.
    func delete(_ id: String) async throws {
        switch try await call({ try await client.deleteArea(path: .init(id: id)) }) {
        case .noContent, .notFound: return
        case .unauthorized: throw await signedOut()
        case .undocumented(let status, _): throw AreaAPIError("Couldn’t remove that area (the server answered \(status)).")
        }
    }

    /// Places a goal in an area, or takes it out of its area with nil.
    func setGoalArea(goalId: String, areaId: String?) async throws {
        let body = Components.Schemas.GoalAreaInput(areaId: areaId ?? "")
        switch try await call({ try await client.setGoalArea(path: .init(id: goalId), body: .json(body)) }) {
        case .noContent: return
        case .unauthorized: throw await signedOut()
        case .notFound(let gone): throw AreaAPIError((try? gone.body.json.error.message) ?? "That goal or area doesn’t exist anymore.")
        case .badRequest(let bad): throw AreaAPIError((try? bad.body.json.error.message) ?? "Couldn’t move that goal.")
        case .undocumented(let status, _): throw AreaAPIError("Couldn’t move that goal (the server answered \(status)).")
        }
    }

    // MARK: Helpers

    private func body(_ input: AreaInput) -> Components.Schemas.AreaInput {
        let now = input.now.trimmingCharacters(in: .whitespacesAndNewlines)
        let want = input.want.trimmingCharacters(in: .whitespacesAndNewlines)
        return Components.Schemas.AreaInput(
            name: input.name.trimmingCharacters(in: .whitespacesAndNewlines),
            icon: .init(rawValue: input.icon) ?? .target02Icon,
            now: now.isEmpty ? nil : input.now,
            want: want.isEmpty ? nil : input.want
        )
    }

    /// Runs a call, turning a dropped connection into a message.
    private func call<T>(_ run: () async throws -> T) async throws -> T {
        do {
            return try await run()
        } catch let error as AreaAPIError {
            throw error
        } catch {
            Log.app.error("Areas: \(error.localizedDescription, privacy: .public)")
            throw AreaAPIError("Couldn’t reach Supervibes. Check your connection.")
        }
    }

    private func signedOut() async -> AreaAPIError {
        await auth.sessionEnded()
        return AreaAPIError("You were signed out.")
    }
}

/// An area call that didn't go through, with what to tell the person.
struct AreaAPIError: Error, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
}
