//
//  FluidAudioDownloader.swift
//  ora
//
//  Thin adapter over FluidAudio's ASR download API. The only file in the
//  project that imports FluidAudio — everything else talks to it through
//  this Swift-native interface so the SDK stays isolated.
//
//  ## Why we report ETA instead of a progress fraction
//
//  Earlier revisions tried to surface FluidAudio's `progress.fractionCompleted`
//  as a circular progress bar. That stream turned out to be unreliable for
//  display: under the pinned SDK (04747b3) the visible behavior was a quick
//  climb to ~5–10 % followed by an immediate snap to 100 %, leaving the
//  spinner running silently for the bulk of the actual download. The likely
//  root cause is that FluidAudio's internal `totalBytes` undercounts the
//  LFS-backed encoder weights file (`Encoder.mlmodelc/weights/weight.bin`,
//  ~445 MB on disk — confirmed via `du`), so `fractionCompleted` reaches its
//  capped 0.5 maximum well before the encoder finishes streaming.
//
//  Rather than chase that upstream bug, we ignore `fractionCompleted` for the
//  download phase entirely and observe the **filesystem** instead, which is
//  ground truth. Two locations are summed:
//
//    1. The model cache directory (files that FluidAudio has finished and
//       moved into place).
//    2. URLSession's in-flight `CFNetworkDownload_*.tmp` files inside the
//       sandbox tmp/caches dirs (the ~445 MB encoder weight is a single
//       URLSession request, so without watching the tmp file the cache dir
//       sits idle for several minutes mid-download).
//
//  A 2-second poll feeds samples into a small sliding window; speed is
//  derived from the oldest/newest pair, ETA from `(total - latest) / speed`.
//  FluidAudio's progress callback is still observed, but only to detect the
//  `.compiling` phase transition so we can flip to `.extracting` and stop the
//  poller.
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

    /// Expected on-disk size for each catalog id, used as the denominator
    /// when computing ETA. Measured 2026-04-08 from a completed install:
    ///
    ///   parakeet-tdt-0.6b-v3:    461 MB on disk
    ///     Encoder.mlmodelc/weights/weight.bin alone:  ~445 MB (96 %)
    ///     Decoder + JointDecision + Preprocessor:     ~16 MB
    ///
    /// If the SDK pin starts pulling a different model set, refresh this
    /// table by running `du -sb` against `AsrModels.defaultCacheDirectory`
    /// after a clean download. Drift up to ~5 % is harmless — the formatter
    /// hides "≈ 0 ETA" as `<3s` and `estimateEta` clamps remaining ≥ 0.
    private static let totalBytesById: [String: Int64] = [
        "parakeet-v3": 461 * 1024 * 1024
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
    /// main actor with `.downloading(eta:)` updates as the disk poller
    /// accumulates samples, and `.extracting` once FluidAudio enters its
    /// CoreML compile phase. Throws `Failure.unsupportedModel` immediately
    /// for unknown ids, `CancellationError` if the surrounding Task is
    /// cancelled, and `Failure.downloadIncomplete` if files are missing
    /// after the call returns.
    func download(
        _ id: String,
        onProgress: @escaping @MainActor (ModelEntry.Status) -> Void
    ) async throws {
        let v = try version(for: id)
        let cacheDir = AsrModels.defaultCacheDirectory(for: v)
        let totalBytes = Self.totalBytesById[id] ?? 0

        // Disk poller. Runs in parallel with `AsrModels.download` and is the
        // sole source of `.downloading(eta:)` updates. Cancelled either when
        // FluidAudio enters the compile phase (see progressHandler below) or
        // when the surrounding function exits via the `defer` below.
        let pollTask = Task<Void, Never> { [totalBytes, cacheDir] in
            // Sliding window of (timestamp, bytes) samples. ~6 samples × 2 s
            // = 12 s of history, which dampens momentary stalls (DNS, TLS,
            // server-side throttling) without making the ETA feel laggy.
            //
            // Seed sample[0] = (now, current on-disk bytes) so the second
            // poll iteration (t ≈ 2 s) already has two samples and can emit
            // a real ETA, instead of waiting until t ≈ 4 s. For a fresh
            // download `bytesDownloaded` is 0; for a resumed download it's
            // the bytes already on disk, which is exactly the right anchor
            // for "speed since the user pressed resume".
            var samples: [(t: Date, bytes: Int64)] = [
                (t: Date(), bytes: Self.bytesDownloaded(cacheDir: cacheDir))
            ]
            // Emit one nil-ETA tick immediately so the UI flips to the
            // .downloading caption ("…") right away, before the first
            // 2-second poll lands.
            await MainActor.run { onProgress(.downloading(eta: nil)) }

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { break }

                let bytes = Self.bytesDownloaded(cacheDir: cacheDir)
                samples.append((t: Date(), bytes: bytes))
                if samples.count > 6 { samples.removeFirst(samples.count - 6) }

                let eta = Self.estimateEta(samples: samples, totalBytes: totalBytes)
                await MainActor.run {
                    // Re-check cancellation inside MainActor.run so a late
                    // landing here can't overwrite a `.extracting` that the
                    // progressHandler dispatched in the meantime.
                    guard !Task.isCancelled else { return }
                    onProgress(.downloading(eta: eta))
                }
            }
        }
        defer { pollTask.cancel() }

        do {
            _ = try await AsrModels.download(version: v, progressHandler: { progress in
                // Phase signal only — `progress.fractionCompleted` is not
                // trustworthy for display under the pinned SDK (see file
                // header). The disk poller is the sole source of byte
                // progress; here we just need to know when downloading
                // finishes so we can flip to .extracting and stop polling.
                guard case .compiling = progress.phase else { return }
                pollTask.cancel()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { onProgress(.extracting) }
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

        guard AsrModels.modelsExist(at: cacheDir, version: v) else {
            throw Failure.downloadIncomplete
        }
    }

    /// Sum of bytes that count toward the download:
    ///   1. Files that FluidAudio has finished and moved into `cacheDir`.
    ///   2. URLSession's in-flight `CFNetworkDownload_*.tmp` files anywhere
    ///      under the sandbox tmp/caches dirs. The encoder weight file
    ///      (~445 MB, ~96 % of the total) is downloaded as a single
    ///      URLSession request, so without (2) the cache dir would sit at
    ///      a few MB for several minutes mid-download and ETA would stall.
    private static func bytesDownloaded(cacheDir: URL) -> Int64 {
        directorySize(at: cacheDir) + inFlightDownloadBytes()
    }

    /// Recursively sums `totalFileAllocatedSize` for every regular file
    /// under `url`. Returns 0 if the directory doesn't exist yet (which is
    /// the normal state at the start of a fresh download).
    private static func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard
                let values = try? fileURL.resourceValues(
                    forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]
                ),
                values.isRegularFile == true
            else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// Sums the sizes of any `CFNetworkDownload_*.tmp` files under the
    /// sandbox's tmp and caches directories. URLSession.download(for:) is
    /// not documented to use a stable location (Apple says only "a temporary
    /// file"), but in practice on macOS sandboxed apps the file lives in
    /// one of these two roots, so we scan both defensively.
    private static func inFlightDownloadBytes() -> Int64 {
        var total: Int64 = 0
        for root in candidateTmpRoots() {
            total += scanCFNetworkDownloads(in: root)
        }
        return total
    }

    private static func candidateTmpRoots() -> [URL] {
        var roots: [URL] = [URL(fileURLWithPath: NSTemporaryDirectory())]
        if let cachesDir = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        ).first {
            roots.append(cachesDir)
        }
        return roots
    }

    private static func scanCFNetworkDownloads(in root: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasPrefix("CFNetworkDownload") else { continue }
            guard
                let values = try? url.resourceValues(
                    forKeys: [.fileSizeKey, .isRegularFileKey]
                ),
                values.isRegularFile == true
            else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    /// Returns the estimated remaining time in seconds, or nil if there
    /// isn't enough signal yet (fewer than 2 samples, no progress between
    /// the oldest and newest sample, or unknown total size).
    private static func estimateEta(
        samples: [(t: Date, bytes: Int64)],
        totalBytes: Int64
    ) -> TimeInterval? {
        guard samples.count >= 2, totalBytes > 0 else { return nil }
        let first = samples.first!
        let last = samples.last!
        let bytesDelta = Double(last.bytes - first.bytes)
        let timeDelta = last.t.timeIntervalSince(first.t)
        guard timeDelta > 0, bytesDelta > 0 else { return nil }
        let speed = bytesDelta / timeDelta // bytes/sec
        let remaining = max(0, Double(totalBytes - last.bytes))
        return remaining / speed
    }
}
