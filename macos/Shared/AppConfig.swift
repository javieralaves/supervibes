import Foundation

enum AppConfig {
    /// The Supervibes server this build talks to: localhost in Debug, production in Release.
    /// Set per configuration in Config/*.xcconfig and carried through Info.plist.
    static var baseURL: URL {
        if let value = Bundle.main.object(forInfoDictionaryKey: "SupervibesBaseURL") as? String,
           let url = URL(string: value), url.scheme != nil {
            return url
        }
        return URL(string: "http://localhost:3000")!
    }
}
