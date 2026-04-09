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

        do {
            _ = try await AsrModels.download(version: v, progressHandler: { progress in
                let status = Self.statusFromProgress(progress)
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

    private static func statusFromProgress(_ progress: DownloadUtils.DownloadProgress) -> ModelEntry.Status {
        switch progress.phase {
        case .listing:
            return .downloading(progress: 0)
        case .downloading:
            // FluidAudio splits its overall fractionCompleted range:
            //   0.0 – 0.5  → network download phase
            //   0.5 – 1.0  → CoreML compile phase
            // (See FluidAudio/Sources/FluidAudio/DownloadUtils.swift:414-418
            // and :460-461 — the constant 0.5 caps the download phase.)
            //
            // We render the network download as a 0–100 % progress ring and
            // the compile phase as a separate spinner (.extracting), so we
            // rescale 0..0.5 → 0..1 here. The min() is a defensive cap.
            return .downloading(progress: min(1.0, progress.fractionCompleted * 2))
        case .compiling:
            return .extracting
        }
    }
}
