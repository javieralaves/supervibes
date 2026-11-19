import AppKit
import Foundation
import Observation

/*
 * Does what the person picked in Settings as sessions start and end (Shared/Models/
 * SessionRoutine.swift has the rules): turns Do Not Disturb on and off through the Shortcuts the
 * app ships, quits apps and reopens them, and runs the person's own Shortcuts. It looks on the
 * app's clock, so unlike notices it only works while the app runs, which a menu bar app does.
 */
@MainActor
@Observable
final class SessionRoutineRunner {
    private(set) var routine = SessionRoutine.load()
    /// The Shortcuts on this Mac, by name; nil until listed.
    private(set) var shortcuts: [String]?
    /// Apps that are open now, to offer in "Add app".
    private(set) var openApps: [SessionRoutine.App] = []

    /// Today's blocks, once fetched; nil before, so a launch mid-session doesn't read an empty day
    /// as the session having ended.
    @ObservationIgnored private var blocks: [Block]?
    /// The stretch last started, by its blocks. Kept across launches, so relaunching mid-session
    /// doesn't start it again.
    @ObservationIgnored private var started: Set<String>
    /// The apps the routine quit, to reopen once the session's over. Kept across launches too.
    @ObservationIgnored private var quit: [String]

    private static let startedKey = "sv-session-routine-started"
    private static let quitKey = "sv-session-routine-quit"
    private nonisolated static let tool = URL(filePath: "/usr/bin/shortcuts")

    init() {
        started = Set(UserDefaults.standard.stringArray(forKey: Self.startedKey) ?? [])
        quit = UserDefaults.standard.stringArray(forKey: Self.quitKey) ?? []
        // Back from adding a Shortcut, or with another app opened, Settings should show it.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.shortcuts != nil else { return }
                self.refreshOptions()
            }
        }
    }

    /// Whether the Shortcuts that switch Do Not Disturb have been added.
    var focusShortcutsAdded: (on: Bool, off: Bool) {
        (shortcuts?.contains(SessionRoutine.focusOn) == true, shortcuts?.contains(SessionRoutine.focusOff) == true)
    }

    func change(_ new: SessionRoutine) {
        routine = new
        new.save()
        Log.routine.info("Routine: do not disturb \(new.doNotDisturb), quit \(new.quitApps.map(\.name), privacy: .public), start \(new.start ?? "none", privacy: .public), end \(new.end ?? "none", privacy: .public)")
    }

    // MARK: - Settings

    /// What Settings offers: the Shortcuts on this Mac and the apps open now.
    func refreshOptions() {
        openApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier && $0.bundleIdentifier != "com.apple.finder" }
            .compactMap { app in
                guard let id = app.bundleIdentifier, let name = app.localizedName else { return nil }
                return SessionRoutine.App(bundleId: id, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        Task { await listShortcuts() }
    }

    /// Opens the next ready-made Do Not Disturb Shortcut still to add; Shortcuts asks to add it.
    func addFocusShortcut() {
        let added = focusShortcutsAdded
        let name = added.on ? SessionRoutine.focusOff : SessionRoutine.focusOn
        guard let url = Bundle.main.url(forResource: name, withExtension: "shortcut") else {
            Log.routine.error("\(name, privacy: .public).shortcut isn't in the app")
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Picks an app from /Applications to quit during sessions.
    func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        var new = routine
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                  !new.quitApps.contains(where: { $0.bundleId == id }) else { continue }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            new.quitApps.append(.init(bundleId: id, name: name))
        }
        change(new)
    }

    func openShortcutsApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    func openFocusSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Sessions

    /// Today's blocks, as the app last fetched them.
    func blocksChanged(_ blocks: [Block]) {
        self.blocks = blocks
        tick(now: Date())
    }

    /// Called on the app's clock: starts or ends the routine as a stretch of sessions does.
    func tick(now: Date) {
        guard let blocks else { return }
        let (action, nowStarted) = SessionStretches.step(blocks: blocks, now: now, started: started)
        if nowStarted != started {
            started = nowStarted
            UserDefaults.standard.set(Array(nowStarted), forKey: Self.startedKey)
        }
        switch action {
        case .start: begin()
        case .end: finish()
        case nil: break
        }
    }

    private func begin() {
        Log.routine.info("Session started")
        if routine.doNotDisturb { run(SessionRoutine.focusOn) }
        quitApps()
        if let start = routine.start { run(start) }
    }

    private func finish() {
        Log.routine.info("Session over")
        if routine.doNotDisturb { run(SessionRoutine.focusOff) }
        reopenApps()
        if let end = routine.end { run(end) }
    }

    private func quitApps() {
        var quitNow: [String] = []
        for app in routine.quitApps {
            for running in NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleId) where running.terminate() {
                quitNow.append(app.bundleId)
            }
        }
        guard !quitNow.isEmpty else { return }
        quit = Array(Set(quit + quitNow))
        UserDefaults.standard.set(quit, forKey: Self.quitKey)
        Log.routine.info("Quit \(quitNow, privacy: .public)")
    }

    private func reopenApps() {
        let toOpen = routine.reopenApps ? quit : []
        quit = []
        UserDefaults.standard.removeObject(forKey: Self.quitKey)
        for id in toOpen {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { continue }
            let configuration = NSWorkspace.OpenConfiguration()
            // Back where it was, without pulling it in front of what you're doing.
            configuration.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
        if !toOpen.isEmpty { Log.routine.info("Reopened \(toOpen, privacy: .public)") }
    }

    // MARK: - Shortcuts

    private func listShortcuts() async {
        let names = await Task.detached { () -> [String]? in
            let process = Process()
            process.executableURL = Self.tool
            process.arguments = ["list"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = Pipe()
            do {
                try process.run()
            } catch {
                return nil
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(decoding: data, as: UTF8.self)
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }.value
        if let names {
            shortcuts = names
        } else {
            Log.routine.error("Couldn't list Shortcuts")
            if shortcuts == nil { shortcuts = [] }
        }
    }

    private func run(_ name: String) {
        Task.detached {
            let process = Process()
            process.executableURL = Self.tool
            process.arguments = ["run", name]
            process.standardOutput = Pipe()
            let errors = Pipe()
            process.standardError = errors
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    Log.routine.info("Ran \(name, privacy: .public)")
                } else {
                    let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    Log.routine.error("\(name, privacy: .public) failed: \(message, privacy: .public)")
                }
            } catch {
                Log.routine.error("Couldn't run \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
