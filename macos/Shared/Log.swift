import os

/// Everything logs under one subsystem so `scripts/logs.sh` can stream just this app.
enum Log {
    static let subsystem = "com.supervibes.mac"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let web = Logger(subsystem: subsystem, category: "web")
    static let widgets = Logger(subsystem: subsystem, category: "widgets")
}
