import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

extension Notification.Name {
    /// Something was saved through the API (a block, a task, a goal…), so anything showing a copy of
    /// the person's data may be out of date. Posted on whatever thread the request finished on.
    static let supervibesDataChanged = Notification.Name("SupervibesDataChanged")
}

/// The generated Supervibes API client (from API/openapi.json), sending the session as a bearer token.
enum APIClient {
    static func make(baseURL: URL, token: @escaping @Sendable () -> String?) -> Client {
        Client(
            serverURL: baseURL,
            // The server sends dates with milliseconds ("2026-11-18T08:00:00.000Z").
            configuration: Configuration(dateTranscoder: .iso8601WithFractionalSeconds),
            // No cookies: the session only ever travels as the bearer token.
            transport: URLSessionTransport(configuration: .init(session: URLSession(configuration: .ephemeral))),
            middlewares: [BearerAuth(token: token), ChangeSignal()]
        )
    }
}

private struct BearerAuth: ClientMiddleware {
    let token: @Sendable () -> String?

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        if let token = token() {
            request.headerFields[.authorization] = "Bearer \(token)"
        }
        return try await next(request, body, baseURL)
    }
}

/// Says when a change has been saved, so the menu bar, widget and notices can catch up straight
/// away rather than at their next scheduled fetch. Every request that isn't a GET and succeeded counts.
private struct ChangeSignal: ClientMiddleware {
    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let (response, responseBody) = try await next(request, body, baseURL)
        if request.method != .get, response.status.kind == .successful {
            NotificationCenter.default.post(name: .supervibesDataChanged, object: nil, userInfo: ["operation": operationID])
        }
        return (response, responseBody)
    }
}
