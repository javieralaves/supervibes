import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

/// The generated Supervibes API client (from API/openapi.json), sending the session as a bearer token.
enum APIClient {
    static func make(baseURL: URL, token: @escaping @Sendable () -> String?) -> Client {
        Client(
            serverURL: baseURL,
            // The server sends dates with milliseconds ("2026-11-18T08:00:00.000Z").
            configuration: Configuration(dateTranscoder: .iso8601WithFractionalSeconds),
            // No cookies: the session only ever travels as the bearer token.
            transport: URLSessionTransport(configuration: .init(session: URLSession(configuration: .ephemeral))),
            middlewares: [BearerAuth(token: token)]
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
