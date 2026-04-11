//
//  Recorder.swift
//  ora
//
//  Captures microphone input via AVAudioEngine and returns a single
//  16 kHz mono Float32 PCM buffer when recording stops. Parakeet (and
//  Whisper, later) both want exactly that format, so we do the sample-
//  rate and channel conversion here once and hand a ready-to-transcribe
//  buffer to STT rather than making every transcriber re-derive it.
//
//  ## Thread model
//
//  The whole target runs with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
//  but AVAudioEngine's input tap callback fires on a real-time audio
//  thread owned by Core Audio — not on the main actor. That callback
//  must stay non-blocking and allocation-light, so the tap pushes raw
//  frames into an `nonisolated(unsafe)` append-only accumulator and the
//  main-actor `stop()` method reads from it after the engine has been
//  halted (at which point the tap is guaranteed not to fire again).
//  The accumulator is only ever touched from one thread at a time by
//  construction: the audio thread appends during `[start, stop)`, the
//  main actor reads after `stop`.
//
//  `onLevel` follows a different pattern: it's a normal main-actor
//  stored property, **not** `nonisolated(unsafe)`. The audio thread
//  never reads `self.onLevel`. Instead, `start()` snapshots the
//  closure into a local on the main actor and threads it through
//  `handleTap`'s parameter list, so the audio thread only ever
//  invokes a closure value that was passed to it. Invocation hops
//  back to the main actor via `DispatchQueue.main.async` (GCD's
//  pre-concurrency bridge accepts non-Sendable closure captures
//  where `Task { @MainActor }` does not — see the design doc's
//  § Audio level meter for the full rationale and rejected
//  alternatives).
//
//  ## Format negotiation
//
//  AVAudioEngine's input node reports the hardware format (typically
//  44.1 or 48 kHz, stereo on some mics). We install the tap in that
//  native format — taps installed in a non-native format silently drop
//  buffers on some devices — and run the frames through an
//  `AVAudioConverter` into our target 16 kHz mono Float32 layout before
//  accumulating. Doing the conversion incrementally (per tap buffer)
//  rather than in one pass at the end keeps peak memory bounded and
//  means `stop()` is effectively free.
//

@preconcurrency import AVFoundation
import Foundation

@MainActor
final class Recorder {
    enum Failure: Error, LocalizedError {
        case notAuthorized
        case engineStartFailed(Error)
        case converterUnavailable
        case notRecording

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Microphone access has not been granted."
            case .engineStartFailed(let error):
                return "Audio engine failed to start: \(error.localizedDescription)"
            case .converterUnavailable:
                return "Could not create an audio format converter."
            case .notRecording:
                return "stop() called while no recording was in progress."
            }
        }
    }

    /// Target format for everything downstream. 16 kHz mono Float32 is
    /// what Parakeet's FluidAudio frontend expects; keeping it fixed
    /// here means STT can assume it.
    ///
    /// These are `nonisolated` so the real-time tap callback (which is
    /// not MainActor-isolated) can read them without hopping actors —
    /// the default MainActor isolation at the target level would
    /// otherwise forbid it.
    nonisolated static let targetSampleRate: Double = 16_000
    nonisolated private static let targetChannels: AVAudioChannelCount = 1

    private let engine = AVAudioEngine()
    private let targetFormat: AVAudioFormat

    /// Append-only accumulator for 16 kHz mono Float32 samples. Written
    /// by the audio thread during [start, stop), read by the main actor
    /// after stop. See thread-model note above.
    private nonisolated(unsafe) var accumulated: [Float] = []
    private var isRunning = false

    /// Called on the main actor with a 0...1 normalized RMS level for
    /// every converted tap buffer while recording. Set before `start()`.
    /// Captured by value at start() time, so mutating after start() has
    /// no effect on the in-flight recording — set it again before the
    /// next start() if you need to swap. See thread-model note for why
    /// this is a normal main-actor property and not nonisolated(unsafe).
    var onLevel: ((Float) -> Void)?

    init() {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: Self.targetChannels,
            interleaved: false
        ) else {
            // Standard PCM formats never fail to construct on Apple
            // platforms; if this ever trips it's a platform bug, not a
            // runtime condition worth recovering from.
            fatalError("Failed to construct target AVAudioFormat (16 kHz mono Float32).")
        }
        self.targetFormat = format
    }

    // MARK: - Lifecycle

    /// Begins recording from the given input device, or the system
    /// default when `deviceID` is `nil`. Must be called after
    /// `MicrophonePermission.request()` has resolved to `true` —
    /// starting the engine without authorization puts the input node
    /// into a zombie state that reports silence forever.
    ///
    /// `deviceID` is an ephemeral `AudioDeviceID` resolved just-in-time
    /// from `InputDeviceStore.resolveSelectedDeviceID()`. If applying
    /// the override fails (e.g. the device was grabbed exclusively
    /// between resolve-time and now), we log the `OSStatus` and
    /// continue with the system default — see the design spec's
    /// silent-fallback policy.
    func start(deviceID: AudioDeviceID? = nil) throws {
        guard MicrophonePermission.status == .authorized else {
            throw Failure.notAuthorized
        }
        if isRunning { return }

        accumulated.removeAll(keepingCapacity: true)

        let input = engine.inputNode

        // Apply the device override BEFORE reading inputFormat — the
        // hardware format is device-specific, and querying it before
        // the override would pin the pipeline to the old default's
        // format.
        if let deviceID {
            Self.applyInputDeviceOverride(on: input, deviceID: deviceID)
        }

        // The hardware format for the input bus. We install the tap in
        // this format and convert downstream — installing a tap in a
        // non-native format is accepted by the API but behaves oddly on
        // some USB interfaces, so don't.
        let inputFormat = input.inputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw Failure.converterUnavailable
        }

        // Snapshot onLevel on the main actor *before* installing the
        // tap. The tap closure captures `levelCallback` (a local), not
        // `self.onLevel`, so the audio thread never reads a main-actor
        // property — it only invokes a closure value that was passed
        // to it. See thread-model note in the file header.
        let levelCallback = self.onLevel

        // 4096 frames ≈ 85 ms at 48 kHz — small enough that a tap-to-
        // stop feels instant, large enough to avoid excessive callback
        // churn on the audio thread.
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.handleTap(buffer: buffer, converter: converter, levelCallback: levelCallback)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw Failure.engineStartFailed(error)
        }
        isRunning = true
    }

    /// Stops recording and returns the captured audio as a single
    /// contiguous 16 kHz mono Float32 PCM buffer. Throws `.notRecording`
    /// if called without a matching `start()`.
    func stop() throws -> AVAudioPCMBuffer {
        guard isRunning else { throw Failure.notRecording }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false

        // After stop() returns, the audio thread is guaranteed not to
        // touch `accumulated` again, so it's safe to read from the main
        // actor without synchronisation.
        let frames = accumulated
        accumulated.removeAll(keepingCapacity: false)

        return Self.makeBuffer(from: frames, format: targetFormat)
    }

    // MARK: - Tap handling

    /// Runs on the real-time audio thread. Converts one input buffer
    /// into the target format, appends its samples to the accumulator,
    /// and (if a `levelCallback` was snapshotted at start() time)
    /// dispatches a normalized RMS level to the main actor. Keep this
    /// path lean — no logging, no allocations beyond the converter's
    /// own scratch buffer and the GCD enqueue.
    private nonisolated func handleTap(
        buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        levelCallback: ((Float) -> Void)?
    ) {
        // Allocate an output buffer sized to what the converter needs
        // for this input chunk. `capacity` is the worst-case frame
        // count at the target rate; the converter writes `frameLength`.
        let ratio = Self.targetSampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1)
        guard capacity > 0,
              let output = AVAudioPCMBuffer(
                pcmFormat: AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: Self.targetSampleRate,
                    channels: 1,
                    interleaved: false
                )!,
                frameCapacity: capacity
              )
        else { return }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            // AVAudioConverter's pull-style callback: return the source
            // buffer once, then signal end-of-stream so it flushes.
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, error == nil,
              let channel = output.floatChannelData?[0] else { return }

        let frameCount = Int(output.frameLength)
        // `accumulated` is only appended on the audio thread and only
        // read by the main actor after the tap has been removed, so
        // this append is safe without locking. See thread-model note.
        accumulated.append(contentsOf: UnsafeBufferPointer(start: channel, count: frameCount))

        // Audio level dispatch. levelCallback was snapshotted on the
        // main actor at start() time, so we never touch self.onLevel
        // here. DispatchQueue.main.async (not Task @MainActor) is the
        // only path that compiles cleanly — Task's @Sendable check
        // rejects capturing the non-Sendable closure value. See
        // design doc § Audio level meter for full reasoning.
        if let levelCallback {
            let rms = Self.computeRMS(channel, count: frameCount)
            let normalized = min(1.0, rms * 8.0)  // 8x gain so quiet speech reaches ~0.6
            DispatchQueue.main.async {
                levelCallback(normalized)
            }
        }
    }

    /// Plain RMS over a Float32 sample buffer. Returns 0 on an empty
    /// buffer (avoids the NaN that would otherwise come from 0/0 and
    /// blow up the SwiftUI waveform binding).
    private nonisolated static func computeRMS(_ samples: UnsafePointer<Float>, count: Int) -> Float {
        guard count > 0 else { return 0 }
        var sumSquares: Float = 0
        for i in 0..<count {
            sumSquares += samples[i] * samples[i]
        }
        return (sumSquares / Float(count)).squareRoot()
    }

    // MARK: - Buffer assembly

    private static func makeBuffer(from frames: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer {
        let capacity = AVAudioFrameCount(max(frames.count, 1))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            // Same rationale as init(): standard PCM formats don't fail
            // to allocate under normal conditions.
            fatalError("Failed to allocate output AVAudioPCMBuffer for \(frames.count) frames.")
        }
        buffer.frameLength = AVAudioFrameCount(frames.count)
        if let channel = buffer.floatChannelData?[0], !frames.isEmpty {
            frames.withUnsafeBufferPointer { src in
                channel.update(from: src.baseAddress!, count: frames.count)
            }
        }
        return buffer
    }

    // MARK: - Device override

    /// Sets `kAudioOutputUnitProperty_CurrentDevice` on the input
    /// node's underlying audio unit. Logs and returns silently on
    /// failure — the caller continues with whatever device the unit
    /// was already bound to (typically the system default).
    private static func applyInputDeviceOverride(
        on input: AVAudioInputNode,
        deviceID: AudioDeviceID
    ) {
        guard let audioUnit = input.audioUnit else {
            NSLog("[Recorder] inputNode.audioUnit was nil; skipping device override")
            return
        }

        var mutableID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            NSLog("[Recorder] AudioUnitSetProperty CurrentDevice failed: OSStatus=\(status); using system default")
        }
    }
}

