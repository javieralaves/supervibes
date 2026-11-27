import Foundation

/// Say it instead, on the plate, as the screens show it: whether it's listening, the last moments of sound for the
/// waveform, and the words still being worked out. Settled words go straight into the plate's text.
struct DictationState: Hashable, Sendable {
    enum Phase: Hashable, Sendable {
        case idle
        /// Asking for the microphone, or getting the speech model ready (a one-off download the first time).
        case preparing
        case listening
        /// Stopped; the last words are settling.
        case finishing
    }

    var phase: Phase = .idle
    /// How loud each recent moment was, 0 to 1, newest last.
    var levels: [Float] = []
    /// What's being said now, before it settles: shown after the plate's text, muted.
    var volatile = ""
    /// Why it couldn't listen.
    var error: String?

    var isActive: Bool { phase != .idle }

    /// How many moments the waveform shows.
    static let levelCount = 44
}
