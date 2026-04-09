//
//  ModelManager.swift
//  ora
//
//  Source of truth for the local + API model catalog. Owns per-entry
//  status, download Tasks, and the FluidAudio adapter. UI reads
//  `catalog` from the environment and calls action methods to mutate it.
//

import Foundation
import Observation

@Observable
@MainActor
final class ModelManager {
    static let shared = ModelManager()

    private(set) var catalog: [ModelEntry]

    private let downloader = FluidAudioDownloader()
    private var tasks: [String: Task<Void, Never>] = [:]

    init() {
        self.catalog = Self.initialCatalog(downloader: FluidAudioDownloader())
    }

    /// Backwards-compat shim so existing call sites keep building until
    /// Task 3 wires the environment-based reads. Will be deleted in Task 3.
    static var mockModels: [ModelEntry] { shared.catalog }

    // MARK: - Catalog seeding

    private static func initialCatalog(downloader: FluidAudioDownloader) -> [ModelEntry] {
        let parakeetV3Status: ModelEntry.Status =
            downloader.isInstalled("parakeet-v3") ? .downloaded : .notDownloaded

        return [
            ModelEntry(
                id: "parakeet-v3",
                name: "Nvidia Parakeet Tdt 0.6B V3",
                description: "Ultra-fast transcription powered by NVIDIA FastConformer. Optimized for conversational speech and voice commands.",
                badge: nil,
                accuracy: 5,
                speed: 5,
                size: "496 MB",
                language: "Multilingual",
                isLocal: true,
                isOnline: false,
                status: parakeetV3Status
            ),
            ModelEntry(
                id: "parakeet-v2",
                name: "Nvidia Parakeet Tdt 0.6B V2",
                description: "Ultra-fast English-only transcription powered by NVIDIA FastConformer V2. Optimized for English dictation and voice commands.",
                badge: nil,
                accuracy: 5,
                speed: 5,
                size: "490 MB",
                language: "English",
                isLocal: true,
                isOnline: false,
                status: .notDownloaded
            ),
            ModelEntry(
                id: "openai-api",
                name: "OpenAI API",
                description: "OpenAI API for transcription. GPT-4o Transcribe is recommended.",
                badge: "Recommended",
                accuracy: 5,
                speed: 4,
                size: "$0.006/min",
                language: "Multilingual",
                isLocal: false,
                isOnline: true,
                status: .downloaded
            ),
            ModelEntry(
                id: "groq-api",
                name: "Groq API",
                description: "Groq API for transcription. Whisper Large v3 is recommended.",
                badge: nil,
                accuracy: 4,
                speed: 4,
                size: "$0.006/min",
                language: "Multilingual",
                isLocal: false,
                isOnline: true,
                status: .downloaded
            ),
        ]
    }
}

extension ModelManager {
    /// Starts a download for `id`. No-op if a download is already in
    /// flight for this id. Reports progress through `catalog[i].status`.
    func download(_ id: String) {
        guard tasks[id] == nil else { return }
        guard let index = catalog.firstIndex(where: { $0.id == id }) else { return }

        // Seed at zero so the UI flips to .downloading immediately even
        // before FluidAudio sends its first progress event.
        catalog[index].status = .downloading(progress: 0)

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.downloader.download(id) { [weak self] status in
                    self?.update(id: id, status: status)
                }
                self.update(id: id, status: .downloaded)
            } catch is CancellationError {
                let lastProgress = self.lastProgress(forId: id)
                self.update(id: id, status: .paused(progress: lastProgress))
            } catch let failure as FluidAudioDownloader.Failure {
                self.update(id: id, status: .error(message: failure.errorDescription ?? "Download failed."))
            } catch {
                self.update(id: id, status: .error(message: error.localizedDescription))
            }
            self.tasks[id] = nil
        }
        tasks[id] = task
    }

    /// Cancels an in-flight download. The Task's catch handler maps
    /// `CancellationError` to `.paused(progress: lastSeen)`.
    func cancel(_ id: String) {
        tasks[id]?.cancel()
    }

    /// Deletes the on-disk model files for `id` and resets status to
    /// `.notDownloaded`. Throws if the deletion itself fails.
    func remove(_ id: String) throws {
        guard let index = catalog.firstIndex(where: { $0.id == id }) else { return }
        if let dir = downloader.cacheDirectory(id),
           FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
        catalog[index].status = .notDownloaded
    }

    // MARK: - Internal helpers

    private func update(id: String, status: ModelEntry.Status) {
        guard let index = catalog.firstIndex(where: { $0.id == id }) else { return }
        catalog[index].status = status
    }

    private func lastProgress(forId id: String) -> Double {
        guard let entry = catalog.first(where: { $0.id == id }) else { return 0 }
        switch entry.status {
        case .downloading(let p), .paused(let p): return p
        default: return 0
        }
    }
}
