//
//  FluidAudioDownloader.swift
//  ora
//
//  Thin adapter over FluidAudio's ASR download API. The only file in the
//  project that imports FluidAudio — everything else talks to it through
//  this Swift-native interface so the SDK stays isolated.
//

import Foundation
import FluidAudio

/// Tracks cumulative byte-weighted progress across the multiple
/// sequential `DownloadUtils.loadModels` calls FluidAudio runs per
/// `AsrModelVersion`. For Parakeet v3 (non-fused), `AsrModels.download`
/// loops over four `DownloadSpec`s — preprocessor, encoder, decoder,
/// joint — and invokes `loadModels` once per spec
/// (FluidAudio AsrModels.swift:437-454, pinned revision 04747b3).
///
/// In current FluidAudio, `loadModelsOnce` checks the *full* required
/// model set on disk before invoking `downloadRepo`
/// (DownloadUtils.swift:191-204). That means the FIRST spec call
/// downloads every required `.mlmodelc` directory in one pass, and
/// the remaining three spec calls short-circuit at the local-cache
/// check and emit only a synthetic `downloading(0,0)` tick at
/// `fractionCompleted = 0.5` followed by their compile events. So in
/// practice we observe a single contiguous downloading stream from
/// 0.0 → 0.5, not four sequential 0→0.5 streams as the spec loop
/// might suggest.
///
/// We still aggregate by spec for two reasons:
///
///   1. Defense in depth — if a future FluidAudio revision narrows
///      `requiredModels` per spec call (so each call genuinely
///      downloads only its own files), the aggregator already knows
///      how to fold per-spec progress into a single ring.
///   2. The synthetic `downloading(0.5, 0, 0)` ticks emitted by
///      cached spec calls would otherwise be misread as a fresh
///      downloading event and could regress the bar; routing them
///      through the aggregator's monotonic update guarantees the
///      ring never goes backwards.
///
/// **Weight table.** Per-spec byte weights, measured 2026-04-08 from
/// HuggingFace's tree API:
///
///   curl -sS "https://huggingface.co/api/models/FluidInference/parakeet-tdt-0.6b-v3-coreml/tree/main/<Spec>.mlmodelc"
///   curl -sS "https://huggingface.co/api/models/FluidInference/parakeet-tdt-0.6b-v3-coreml/tree/main/<Spec>.mlmodelc/weights"
///
/// summing the `size` field of every file in each spec directory:
///
///   preprocessor:    ~522 KB    ( 0.11 %)
///   encoder:         ~446 MB    (92.38 %)    ← dominant
///   decoder:         ~23.6 MB   ( 4.89 %)
///   joint:           ~12.7 MB   ( 2.62 %)
///   total:           ~483 MB
///
/// Because today's FluidAudio downloads everything in spec 0, we use
/// `[1.0, 0, 0, 0]` rather than the per-mlmodelc byte ratios — that
/// way the ring fills 0 → 100 % across spec 0's downloading stream
/// and the cached spec 2/3/4 ticks contribute zero. If a future
/// revision actually splits downloads per spec, swap to the
/// `bytesPerSpec` ratios in the comment above and the aggregator's
/// boundary detection will start firing.
private final class ProgressAggregator {
    /// Weight per spec for Parakeet v3 non-fused. Index matches the
    /// order FluidAudio runs them in `AsrModels.swift:437-443`:
    /// `[preprocessor, encoder, decoder, joint]`.
    ///
    /// See the type-level comment for why this is `[1.0, 0, 0, 0]`
    /// instead of the byte-ratio table `[0.0011, 0.9238, 0.0489, 0.0262]`.
    private static let weights: [Double] = [1.0, 0.0, 0.0, 0.0]

    /// Threshold for detecting a spec boundary. Progress within a
    /// single spec is monotonically increasing, so any sample that's
    /// more than `boundaryDropThreshold` below the previous one is a
    /// reset to the next spec. 0.05 is comfortably above URLSession
    /// jitter but well below a real spec reset (~1.0 → 0.0).
    private static let boundaryDropThreshold: Double = 0.05

    private var currentSpec: Int = 0
    private var lastSpecFraction: Double = 0
    private var completedWeight: Double = 0
    private var monotonicFloor: Double = 0
    private var warnedAboutSpecOverflow: Bool = false

    /// Current monotonic ring fraction, 0..1. Used by the listing
    /// branch so a fresh listing event mid-download doesn't snap the
    /// ring back to 0 %.
    var currentFraction: Double { monotonicFloor }

    /// Updates the aggregator with a new downloading-phase sample
    /// (FluidAudio's raw `fractionCompleted` for the current spec,
    /// 0.0..0.5 since FluidAudio reserves the top half for compile).
    /// Returns the overall smooth fraction across all specs, 0..1.
    func update(specFraction rawFraction: Double) -> Double {
        // FluidAudio clamps each spec's download phase to 0.0..0.5.
        // Rescale to 0..1 within the current spec so our aggregator
        // sees clean per-spec progress.
        let rescaled = min(1.0, rawFraction * 2)

        // Detect a spec boundary: a significant drop from the last
        // sample means FluidAudio finished one spec and started the
        // next one. (Under current FluidAudio behavior this never
        // fires — see the type-level comment — but we keep the logic
        // so the aggregator stays correct if FluidAudio changes.)
        if rescaled + Self.boundaryDropThreshold < lastSpecFraction {
            completedWeight += weight(for: currentSpec)
            currentSpec += 1
            if currentSpec >= Self.weights.count && !warnedAboutSpecOverflow {
                // Weight table is stale relative to the pinned SDK —
                // FluidAudio is running more specs than we have weights
                // for. The aggregator will pin at the monotonic floor
                // until the real download finishes instead of advancing.
                print(
                    "warning: FluidAudio.ProgressAggregator saw more specs than expected weights — "
                    + "update the table in FluidAudioDownloader.swift after checking AsrModels.swift specs definition"
                )
                warnedAboutSpecOverflow = true
            }
        }
        lastSpecFraction = rescaled

        let currentContribution = weight(for: currentSpec) * rescaled
        let candidate = min(1.0, completedWeight + currentContribution)
        // The bar never moves backwards. This protects against the
        // synthetic downloading(0.5, 0, 0) ticks that cached spec
        // calls emit at DownloadUtils.swift:202-203 — those ticks
        // map to rescaled=1.0 and would be fine, but if anything
        // else ever produces a momentary low value (URLSession
        // retry, partial range request, etc.) the floor catches it.
        monotonicFloor = max(monotonicFloor, candidate)
        return monotonicFloor
    }

    private func weight(for index: Int) -> Double {
        guard index < Self.weights.count else { return 0 }
        return Self.weights[index]
    }
}

struct FluidAudioDownloader {
    enum Failure: Error, LocalizedError {
        case unsupportedModel(String)
        case downloadIncomplete
        case underlying(Error)

        var errorDescription: String? {
            switch self {
            case .unsupportedModel:
                return "Not available in this build."
            case .downloadIncomplete:
                return "Download incomplete, try again."
            case .underlying(let error):
                return error.localizedDescription
            }
        }
    }

    /// Maps catalog ids to FluidAudio model versions. Adding a new local
    /// model means adding a row here and a catalog entry in `ModelManager`.
    private static let versionsById: [String: AsrModelVersion] = [
        "parakeet-v3": .v3
    ]

    private func version(for id: String) throws -> AsrModelVersion {
        guard let v = Self.versionsById[id] else {
            throw Failure.unsupportedModel(id)
        }
        return v
    }
}

extension FluidAudioDownloader {
    func isInstalled(_ id: String) -> Bool {
        guard let v = try? version(for: id) else { return false }
        let dir = AsrModels.defaultCacheDirectory(for: v)
        return AsrModels.modelsExist(at: dir, version: v)
    }

    func cacheDirectory(_ id: String) -> URL? {
        guard let v = try? version(for: id) else { return nil }
        return AsrModels.defaultCacheDirectory(for: v)
    }
}

extension FluidAudioDownloader {
    /// Downloads the model identified by `id`, calling `onProgress` on the
    /// main actor each time FluidAudio reports a phase or fraction change.
    /// Throws `Failure.unsupportedModel` immediately for unknown ids,
    /// `CancellationError` if the surrounding Task is cancelled, and
    /// `Failure.downloadIncomplete` if files are missing after the call
    /// returns.
    func download(
        _ id: String,
        onProgress: @escaping @MainActor (ModelEntry.Status) -> Void
    ) async throws {
        let v = try version(for: id)
        // Fresh aggregator per download — `ProgressAggregator` is a
        // class so the closure below captures it by reference and
        // mutations inside `update(specFraction:)` persist across
        // callbacks.
        let aggregator = ProgressAggregator()

        do {
            _ = try await AsrModels.download(version: v, progressHandler: { progress in
                let status = Self.status(from: progress, aggregator: aggregator)
                // Hop to the main actor via DispatchQueue to preserve FIFO
                // order. An unstructured Task { @MainActor in ... } could in
                // principle reorder closely-spaced progress events, which
                // would be visible as a stuck final state (e.g., extracting
                // landing before the last downloading tick).
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        onProgress(status)
                    }
                }
            })
        } catch is CancellationError {
            // Re-throw as-is so the caller sees CancellationError rather than
            // a Failure.underlying wrapper — ModelManager relies on this to
            // transition to .paused instead of .error.
            throw CancellationError()
        } catch {
            throw Failure.underlying(error)
        }

        let dir = AsrModels.defaultCacheDirectory(for: v)
        guard AsrModels.modelsExist(at: dir, version: v) else {
            throw Failure.downloadIncomplete
        }
    }

    private static func status(
        from progress: DownloadUtils.DownloadProgress,
        aggregator: ProgressAggregator
    ) -> ModelEntry.Status {
        switch progress.phase {
        case .listing:
            // Use the aggregator's current floor instead of resetting
            // to 0. FluidAudio emits a listing event at the start of
            // every spec call (DownloadUtils.swift:360), and a hard
            // reset would snap the ring back to 0 % between specs.
            return .downloading(progress: aggregator.currentFraction)
        case .downloading:
            // NOTE: we ignore progress.phase's (completedFiles, totalFiles)
            // here. FluidAudio reports them per-spec, not aggregated across
            // the 4 sequential specs it runs for Parakeet v3, so file
            // counts aren't useful at the adapter layer. The byte fraction
            // (after rescale + cross-spec aggregation) is the right signal.
            let overall = aggregator.update(specFraction: progress.fractionCompleted)
            return .downloading(progress: overall)
        case .compiling:
            return .extracting
        }
    }
}
