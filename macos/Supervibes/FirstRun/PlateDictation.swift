@preconcurrency import AVFoundation
import Foundation
import Observation
import Speech

/// Say it instead, on the plate: the microphone, through Apple's on-device speech recognition (SpeechAnalyzer, macOS
/// 26), into the plate's text. Free and private: nothing leaves the Mac, and the model is a one-off download per
/// language, made by the system. Words that have settled are handed to `onSettled` as they come; the words still being
/// worked out are kept in `state.volatile`, to show after them muted, as Claude's own dictation does.
@MainActor
@Observable
final class PlateDictation {
    private(set) var state = DictationState()
    /// Settled words, to add to the plate.
    @ObservationIgnored var onSettled: (String) -> Void = { _ in }

    @ObservationIgnored private var audio: DictationAudio?
    @ObservationIgnored private var analyzer: SpeechAnalyzer?
    @ObservationIgnored private var results: Task<Void, Never>?
    @ObservationIgnored private var run: Task<Void, Never>?

    func toggle() {
        state.isActive ? stop() : start()
    }

    func start() {
        guard !state.isActive else { return }
        state = DictationState(phase: .preparing, levels: Array(repeating: 0, count: DictationState.levelCount))
        run = Task { await listen() }
    }

    /// Stops listening; the last words settle, then it's idle again.
    func stop() {
        switch state.phase {
        case .idle, .finishing: return
        case .preparing:
            run?.cancel()
            teardown()
        case .listening:
            state.phase = .finishing
            Task { await finish() }
        }
    }

    /// Stops and waits for the last words, before the plate is sorted.
    func finishIfNeeded() async {
        guard state.isActive else { return }
        if state.phase == .listening { state.phase = .finishing }
        await finish()
    }

    // MARK: Listening

    private func listen() async {
        guard await microphoneAllowed() else {
            return fail("Supervibes needs the microphone to listen. Allow it in System Settings, under Privacy & Security, Microphone.")
        }
        guard SpeechTranscriber.isAvailable else { return fail("Speech recognition isn’t available on this Mac.") }
        do {
            // The Mac's language if it's supported, US English if not.
            var locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)
            if locale == nil { locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en_US")) }
            let language = locale ?? Locale(identifier: "en_US")
            let transcriber = SpeechTranscriber(
                locale: language, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults], attributeOptions: []
            )
            // The first time, the system downloads the model for the language.
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
            guard !Task.isCancelled else { return }
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                return fail("Couldn’t start listening.")
            }

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            self.analyzer = analyzer
            results = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        let text = String(result.text.characters)
                        if result.isFinal {
                            self?.settle(text)
                        } else {
                            self?.state.volatile = text
                        }
                    }
                } catch {
                    Log.app.error("Dictation results: \(error.localizedDescription, privacy: .public)")
                }
            }
            try await analyzer.prepareToAnalyze(in: format)

            let audio = DictationAudio()
            self.audio = audio
            try await analyzer.start(inputSequence: audio.stream)
            try audio.start(converting: format) { [weak self] level in
                Task { @MainActor in self?.add(level) }
            }
            guard !Task.isCancelled else { return teardown() }
            state.phase = .listening
            Log.app.info("Dictation: listening in \(language.identifier, privacy: .public)")
        } catch {
            Log.app.error("Dictation: \(error.localizedDescription, privacy: .public)")
            fail("Couldn’t start listening. Try again, or type instead.")
        }
    }

    private func finish() async {
        audio?.stop()
        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch {
            Log.app.error("Dictation finishing: \(error.localizedDescription, privacy: .public)")
        }
        await results?.value
        // Anything still unsettled is kept, as said.
        if !state.volatile.isEmpty { settle(state.volatile) }
        teardown()
    }

    private func settle(_ text: String) {
        state.volatile = ""
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !words.isEmpty { onSettled(words) }
    }

    private func add(_ level: Float) {
        guard state.phase == .listening || state.phase == .finishing else { return }
        state.levels.append(level)
        if state.levels.count > DictationState.levelCount { state.levels.removeFirst(state.levels.count - DictationState.levelCount) }
    }

    private func fail(_ message: String) {
        teardown()
        state.error = message
    }

    private func teardown() {
        audio?.stop()
        audio = nil
        analyzer = nil
        results?.cancel()
        results = nil
        run = nil
        state = DictationState()
    }

    private func microphoneAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }
}

/// The microphone, as the analyzer wants it: each buffer converted to its format and passed on, with how loud it was.
/// Runs on the audio thread, so it holds no main-actor state.
private final class DictationAudio: @unchecked Sendable {
    let stream: AsyncStream<AnalyzerInput>
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var running = false

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self, bufferingPolicy: .unbounded)
    }

    func start(converting format: AVAudioFormat, onLevel: @escaping @Sendable (Float) -> Void) throws {
        let input = engine.inputNode
        let natural = input.outputFormat(forBus: 0)
        converter = natural == format ? nil : AVAudioConverter(from: natural, to: format)
        input.installTap(onBus: 0, bufferSize: 1024, format: natural) { [weak self] buffer, _ in
            guard let self else { return }
            onLevel(Self.level(of: buffer))
            if let converted = self.convert(buffer, to: format) {
                self.continuation.yield(AnalyzerInput(buffer: converted))
            }
        }
        engine.prepare()
        try engine.start()
        running = true
    }

    func stop() {
        guard running else { return continuation.finish() }
        running = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation.finish()
    }

    private func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        // The converter asks for input until told there's none for now; this buffer is given once.
        final class Once: @unchecked Sendable { var given = false }
        let once = Once()
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if once.given {
                status.pointee = .noDataNow
                return nil
            }
            once.given = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && output.frameLength > 0 ? output : nil
    }

    /// How loud a buffer is, 0 to 1: its loudness from about -50 dB up.
    private static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        let decibels = 20 * log10(max(rms, 0.000_01))
        return min(max((decibels + 50) / 45, 0), 1)
    }
}
