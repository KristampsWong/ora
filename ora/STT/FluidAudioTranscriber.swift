//
//  FluidAudioTranscriber.swift
//  ora
//
//  Concrete `Transcriber` backed by FluidAudio's Parakeet TDT 0.6B v3
//  pipeline. This and `FluidAudioDownloader` are the only files in the
//  project that import FluidAudio — keeping the SDK isolated to the
//  Models/ and STT/ adapters means the rest of the app talks to plain
//  Swift types and doesn't need to learn FluidAudio's vocabulary.
//
//  ## Lazy model loading
//
//  Loading the four CoreML models (preprocessor, encoder, decoder,
//  joint) takes ~1–2 s on first launch on an M-series Mac and is
//  amortised across every subsequent transcription. We do it lazily
//  on the first `transcribe(_:)` call rather than at app launch so
//  that:
//
//   1. Cold-launch latency is paid by the first dictation, not by
//      the menu bar appearing — better for users who launch Ora and
//      then walk away.
//   2. We don't have to handle "model isn't downloaded yet" at app
//      startup. The first `transcribe` either finds the cache and
//      loads it, or throws `.modelNotDownloaded`.
//
//  Concurrent calls to `transcribe(_:)` while the model is still
//  loading share a single `Task` via `loadTask`, so we never start
//  the load twice. Once loaded, `manager` is reused for the lifetime
//  of the process.
//
//  ## Decoder state per call
//
//  TDT decoder state (`TdtDecoderState`) is meant to carry context
//  across chunks of a streaming transcription. Hold-to-talk gives us
//  one independent utterance per release, with no continuity from
//  the previous one, so we allocate a fresh state per `transcribe`
//  call. The cost is negligible (~150 KB of zeroed MLMultiArrays).
//
//  ## Sample extraction
//
//  We pull `[Float]` out of the `AVAudioPCMBuffer` on the main actor
//  before hopping to `AsrManager` (an actor). Passing the array
//  instead of the buffer sidesteps the AVFoundation Sendable warning
//  and matches AsrManager's `transcribe([Float], decoderState:)`
//  overload directly. Recorder already guarantees the buffer is
//  16 kHz mono Float32 (the format Parakeet wants), so no resample
//  is needed here.
//

import AVFoundation
@preconcurrency import FluidAudio

@MainActor
final class FluidAudioTranscriber: Transcriber {
    enum Failure: Error, LocalizedError {
        case modelNotDownloaded
        case emptyAudio
        case loadFailed(Error)
        case inferenceFailed(Error)

        var errorDescription: String? {
            switch self {
            case .modelNotDownloaded:
                return "The Parakeet model isn't downloaded yet. Open Settings ▸ Models and download it before dictating."
            case .emptyAudio:
                return "The recording was empty — no audio frames to transcribe."
            case .loadFailed(let error):
                return "Failed to load the speech model: \(error.localizedDescription)"
            case .inferenceFailed(let error):
                return "Transcription failed: \(error.localizedDescription)"
            }
        }
    }

    private let modelId: String
    private let downloader: FluidAudioDownloader

    /// The loaded `AsrManager` once `ensureLoaded()` has run successfully.
    /// Holds for the rest of the process — we never tear down on idle for
    /// v1 because the loaded models sit at ~66 MB on the ANE and reloading
    /// them costs more than keeping them resident.
    private var manager: AsrManager?

    /// In-flight load task, if any. Concurrent `transcribe(_:)` callers
    /// await this same task instead of triggering a duplicate load.
    /// Cleared on success and on failure (so a retry can re-attempt).
    private var loadTask: Task<AsrManager, Error>?

    init(modelId: String = "parakeet-v3", downloader: FluidAudioDownloader = FluidAudioDownloader()) {
        self.modelId = modelId
        self.downloader = downloader
    }

    // MARK: - Transcriber

    func transcribe(_ buffer: AVAudioPCMBuffer) async throws -> String {
        // Pull samples out on the main actor before crossing into the
        // AsrManager actor — `[Float]` is Sendable, AVAudioPCMBuffer is
        // not. Recorder hands us 16 kHz mono Float32 already, so this
        // is a single channel-pointer copy.
        let samples = Self.extractFloats(from: buffer)
        guard !samples.isEmpty else { throw Failure.emptyAudio }

        let manager = try await ensureLoaded()

        // Fresh decoder state per utterance — see file header. `make`
        // is the non-throwing variant; the underlying allocation only
        // fails on actual OOM, which `make` chooses to crash on rather
        // than thread an Error through every call site.
        var state = TdtDecoderState.make()

        do {
            let result = try await manager.transcribe(samples, decoderState: &state)
            return result.text
        } catch {
            throw Failure.inferenceFailed(error)
        }
    }

    // MARK: - Lazy model load

    /// Returns the loaded `AsrManager`, loading it on the first call.
    /// Subsequent calls (and concurrent callers racing the first) return
    /// immediately from the cached value or share the in-flight task.
    private func ensureLoaded() async throws -> AsrManager {
        if let manager { return manager }
        if let loadTask { return try await loadTask.value }

        // Surface the "user hasn't clicked Download yet" case as a
        // distinct error before we try to read from the cache dir.
        // FluidAudio would throw a less actionable file-not-found here.
        guard downloader.isInstalled(modelId) else {
            throw Failure.modelNotDownloaded
        }

        let task = Task<AsrManager, Error> {
            do {
                // `loadFromCache(version: .v3)` reads the four mlmodelc
                // bundles that `AsrModels.download(version: .v3)` left
                // in the default cache directory. The two are a matched
                // pair — same version enum, same on-disk layout.
                let models = try await AsrModels.loadFromCache(version: .v3)
                let manager = AsrManager(config: .default)
                try await manager.loadModels(models)
                return manager
            } catch {
                throw Failure.loadFailed(error)
            }
        }
        loadTask = task

        do {
            let loaded = try await task.value
            manager = loaded
            loadTask = nil
            return loaded
        } catch {
            // Clear the task on failure so a future call can try again
            // (e.g. after the user re-downloads). Without this, the
            // failed task would be cached forever and every retry would
            // get the same error.
            loadTask = nil
            throw error
        }
    }

    // MARK: - Buffer → samples

    /// Copies channel 0 of a Float32 PCM buffer into a flat `[Float]`.
    /// Recorder guarantees mono, so channel 0 is the entire signal.
    /// Returns an empty array if the buffer's channel data is missing
    /// (which shouldn't happen with our Recorder, but is the safer
    /// failure mode than crashing on a force-unwrap).
    private static func extractFloats(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: count))
    }
}
