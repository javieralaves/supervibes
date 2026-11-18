import Foundation
import Observation
import SwiftUI

/// App-wide state for the native surfaces. Runs on fixtures until the API exists.
@MainActor
@Observable
final class AppModel {
    private(set) var now = Date()
    private let blocks: [Block]

    init() {
        // Lay the fixture day out around launch, so the menu bar has a live countdown to show.
        blocks = Fixtures.blocks(around: Date())
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self else { return }
                self.now = Date()
            }
        }
    }

    var current: Block? {
        blocks.first { $0.isHappening(at: now) }
    }

    var upcoming: [Block] {
        blocks.filter { $0.start > now }
    }

    /// What the menu bar item reads: the time left in the current block, or the time of the next one.
    var menuBarTitle: Text {
        if let current {
            return Text("\(Image(systemName: "timer")) \(Block.remaining(minutes: current.minutesLeft(at: now)))")
        }
        if let next = upcoming.first {
            return Text("\(Image(systemName: "calendar")) \(next.start.formatted(date: .omitted, time: .shortened))")
        }
        return Text(Image(systemName: "calendar"))
    }
}
