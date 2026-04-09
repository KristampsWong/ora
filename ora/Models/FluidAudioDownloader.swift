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
        case .downloading(let completedFiles, let totalFiles):
            // We deliberately IGNORE progress.fractionCompleted here.
            //
            // FluidAudio sums file sizes at DownloadUtils.swift:366 to
            // compute totalBytes, but for LFS-tracked models (all Parakeet
            // weights live in .mlmodelc/weights/*.bin and are LFS pointers)
            // HuggingFace's tree API returns the pointer-file size (~130 B)
            // instead of the resolved LFS size. totalBytes ends up a few
            // KB instead of ~496 MB, so the fraction pins to the 0.5 cap
            // at DownloadUtils.swift:418 after the first LFS file starts
            // and the ring jumps to 100 % while the real download is still
            // running silently underneath.
            //
            // The file count is reliable — FluidAudio tracks it directly
            // from the filesToDownload list, no LFS weirdness involved.
            // Ring advances in discrete steps (one per file completion),
            // which is honest about what's happening.
            let fraction = totalFiles > 0
                ? Double(completedFiles) / Double(totalFiles)
                : 0
            return .downloading(progress: fraction)
        case .compiling:
            return .extracting
        }
    }
}
