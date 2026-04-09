//
//  DictationCoordinator.swift
//  ora
//
//  The M6 vertical slice. Owns the dictation pipeline and the overlay
//  pill, runs a four-state machine driven by the global hotkey, and
//  funnels every state change through a single transition method so
//  side effects are easy to reason about.
//
//  ## State machine
//
//      idle ──onPress──▶ [preflight]
//                           │
//                ┌──────────┴──────────┐
//                │                     │
//                ▼                     ▼
//             recording             error(_)
//                │                     │
//             onRelease           (2s timer or
//                │                  re-press)
//                ▼                     │
//          transcribing                ▼
//             │   │                   idle
//        success  failure
//             │   │
//             ▼   ▼
//           idle  error(_)
//
//  See `docs/2026-04-09-m6-dictation-coordinator-design.md` for the
//  full transitions table, the rationale for each design decision,
//  and the explicit non-goals.
//
//  ## Threading
//
//  Everything here is `@MainActor`. Carbon hotkey callbacks already
//  arrive on the main thread (HotkeyService bridges via
//  `MainActor.assumeIsolated`). The transcribe + paste pipeline runs
//  in a Task that hops to background for inference and returns to
//  main for the paste step. The error auto-dismiss is also a main-
//  actor Task using `Task.sleep`.
//

import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class DictationCoordinator {
    // MARK: - State

    enum State: Equatable {
        case idle
        case recording
        case transcribing       // also covers the paste tail
        case error(ErrorKind)
    }

    enum ErrorKind: Equatable {
        case noMic
        case noAccessibility
        case noModel
        case generic(String)
    }

    private(set) var state: State = .idle

    // MARK: - Dependencies (owned)

    private let hotkey: HotkeyService
    private let recorder: Recorder
    private let transcriber: FluidAudioTranscriber
    private let paster: Paster
    private let overlay: RecordingOverlayController
    private let modelManager: ModelManager
    private let preferences: Preferences

    // MARK: - In-flight task bookkeeping

    /// The transcribe + paste pipeline launched on hotkey release.
    /// Cancelled on coordinator deinit (defensive — coordinator is
    /// process-lifetime in practice).
    private var transcribeTask: Task<Void, Never>?

    /// The 2s auto-dismiss timer for error states. Cancelled on every
    /// state transition that lands somewhere new, so a re-press during
    /// the error window cleanly replaces it.
    private var errorDismissTask: Task<Void, Never>?

    // MARK: - Init

    /// Convenience init used at app launch. Constructs every dependency
    /// inside the main-actor body so default-argument evaluation never
    /// crosses an isolation boundary (which trips strict-concurrency).
    convenience init() {
        self.init(
            hotkey: HotkeyService(),
            recorder: Recorder(),
            transcriber: FluidAudioTranscriber(),
            paster: Paster(),
            overlay: RecordingOverlayController(),
            modelManager: .shared,
            preferences: .shared
        )
    }

    /// Designated init used by tests / harnesses to inject fakes. No
    /// default arguments — see `convenience init()` above for the
    /// reason.
    init(
        hotkey: HotkeyService,
        recorder: Recorder,
        transcriber: FluidAudioTranscriber,
        paster: Paster,
        overlay: RecordingOverlayController,
        modelManager: ModelManager,
        preferences: Preferences
    ) {
        self.hotkey = hotkey
        self.recorder = recorder
        self.transcriber = transcriber
        self.paster = paster
        self.overlay = overlay
        self.modelManager = modelManager
        self.preferences = preferences
    }

    // No deinit: under strict concurrency a `@MainActor` class's deinit
    // is nonisolated and cannot touch the in-flight task properties.
    // The coordinator is process-lifetime in practice so the defensive
    // cancellation buys nothing — drop it rather than fight the
    // isolation rules.

    // MARK: - Lifecycle

    /// Wires the audio level callback, registers the global hotkey,
    /// and starts listening for press/release. Call once at app
    /// launch from `AppDelegate.applicationDidFinishLaunching`.
    func start() {
        recorder.onLevel = { [weak self] level in
            self?.overlay.state.audioLevel = level
        }

        hotkey.onPress = { [weak self] in
            self?.handlePress()
        }
        hotkey.onRelease = { [weak self] in
            self?.handleRelease()
        }
        hotkey.register(.optionSpace)
    }

    // MARK: - Hotkey handlers

    private func handlePress() {
        switch state {
        case .recording, .transcribing:
            // Busy — silently ignore. See design doc § Why ignore
            // re-press while busy.
            return

        case .idle:
            startNewDictation()

        case .error:
            // Error is treated as a decorated idle: cancel the dismiss
            // timer and re-run preflight from the top. See design doc
            // § Why error(_) accepts re-press immediately.
            errorDismissTask?.cancel()
            errorDismissTask = nil
            startNewDictation()
        }
    }

    private func handleRelease() {
        guard case .recording = state else {
            // Release without a matching record start — either we
            // never made it past preflight, or we're already in
            // transcribing/error/idle. Nothing to stop.
            return
        }

        do {
            let buffer = try recorder.stop()
            transition(to: .transcribing)
            startTranscribePipeline(buffer: buffer)
        } catch {
            transition(to: .error(.generic(Self.shortMessage(for: error))))
        }
    }

    // MARK: - Press path: preflight + recorder.start

    private func startNewDictation() {
        // 1. Microphone permission
        switch MicrophonePermission.status {
        case .notDetermined:
            // Fire-and-forget: shows the system dialog. The current
            // press is doomed (the user can't grant + we can't await
            // a sync hotkey callback), but the next press after the
            // user clicks Allow will hit the happy path.
            Task { _ = await MicrophonePermission.request() }
            transition(to: .error(.noMic))
            return
        case .denied:
            transition(to: .error(.noMic))
            return
        case .authorized:
            break
        }

        // 2. Accessibility (paste) permission
        if !Paster.isTrusted {
            // Fire-and-forget: opens the System Settings list and
            // adds Ora to it. The user has to enable us manually,
            // then re-press.
            _ = Paster.requestTrust(prompt: true)
            transition(to: .error(.noAccessibility))
            return
        }

        // 3. Selected model installed?
        let selectedId = preferences.selectedModelId ?? "parakeet-v3"
        if !modelManager.isInstalled(selectedId) {
            transition(to: .error(.noModel))
            return
        }

        // 4. Start recording. This is the only check that needs to
        //    talk to AVAudioEngine — anything that goes wrong from
        //    here is generic.
        do {
            try recorder.start()
            transition(to: .recording)
        } catch {
            transition(to: .error(.generic(Self.shortMessage(for: error))))
        }
    }

    // MARK: - Release path: transcribe + paste pipeline

    private func startTranscribePipeline(buffer: AVAudioPCMBuffer) {
        transcribeTask?.cancel()
        transcribeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await self.transcriber.transcribe(buffer)

                // The transcriber holds main-actor isolation, so we're
                // already back on main here. Empty result is treated
                // as success-with-nothing-to-paste.
                if text.isEmpty {
                    self.transition(to: .idle)
                    return
                }

                try await self.paster.paste(text)
                self.transition(to: .idle)
            } catch let failure as FluidAudioTranscriber.Failure {
                switch failure {
                case .modelNotDownloaded:
                    self.transition(to: .error(.noModel))
                case .emptyAudio:
                    // No frames captured — treat as a clean idle, not
                    // an error. The user pressed and released too fast.
                    self.transition(to: .idle)
                case .loadFailed, .inferenceFailed:
                    self.transition(to: .error(.generic(Self.shortMessage(for: failure))))
                }
            } catch let failure as Paster.Failure {
                switch failure {
                case .accessibilityNotTrusted:
                    // Dead-defensive in practice — preflight already
                    // checked Paster.isTrusted, so we only land here
                    // if the user toggled Ora off in System Settings
                    // *during* an in-flight dictation. Handle anyway
                    // because Paster.paste's throw is part of its
                    // public contract.
                    _ = Paster.requestTrust(prompt: true)
                    self.transition(to: .error(.noAccessibility))
                case .eventCreationFailed:
                    self.transition(to: .error(.generic(Self.shortMessage(for: failure))))
                }
            } catch {
                self.transition(to: .error(.generic(Self.shortMessage(for: error))))
            }
        }
    }

    // MARK: - State transitions

    /// The single mutation point. Every code path that wants to change
    /// `state` goes through here so the side effects (overlay update,
    /// error dismiss timer) live in exactly one place.
    private func transition(to newState: State) {
        state = newState

        switch newState {
        case .idle:
            errorDismissTask?.cancel()
            errorDismissTask = nil
            dismiss()

        case .recording:
            errorDismissTask?.cancel()
            errorDismissTask = nil
            present(.recording)

        case .transcribing:
            errorDismissTask?.cancel()
            errorDismissTask = nil
            present(.transcribing)

        case .error(let kind):
            present(overlayPhase(for: kind))
            scheduleErrorDismiss()
        }
    }

    private func overlayPhase(for kind: ErrorKind) -> OverlayPhase {
        switch kind {
        case .noMic: return .errorNoMic
        case .noAccessibility: return .errorNoAccessibility
        case .noModel: return .errorNoModel
        case .generic(let msg): return .errorGeneric(msg)
        }
    }

    private func scheduleErrorDismiss() {
        errorDismissTask?.cancel()
        errorDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            // Only dismiss if we're still in an error state. A re-press
            // that landed us back in .recording shouldn't be wiped out
            // by a stale dismiss task.
            if case .error = self.state {
                self.transition(to: .idle)
            }
        }
    }

    // MARK: - Overlay helpers (the present/dismiss contract)

    /// Sets the overlay's visible phase, picking between the
    /// idempotent panel creator (`show(phase:)`) and live state
    /// mutation (`state.phase = X`) based on whether the panel is
    /// already on screen. See design doc § Overlay API contract.
    private func present(_ phase: OverlayPhase) {
        if overlay.isShowing {
            overlay.state.phase = phase
        } else {
            overlay.show(phase: phase)
        }
    }

    /// Removes the overlay panel from screen. Called on the idle
    /// transition.
    private func dismiss() {
        overlay.hide()
    }

    // MARK: - Error message formatting

    /// Caps an error's localized description at 32 characters so the
    /// generic-error pill stays visually narrow. Cuts mid-word; v0.1
    /// nit, M7 polish.
    private static func shortMessage(for error: Error) -> String {
        let raw = error.localizedDescription
        return String(raw.prefix(32))
    }
}
