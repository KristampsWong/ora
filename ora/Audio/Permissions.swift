//
//  Permissions.swift
//  ora
//
//  Shared, observable snapshot of the two permissions the onboarding
//  flow needs to talk about: microphone (via AVFoundation) and
//  accessibility (via AXIsProcessTrusted). This is a UI-layer concern
//  only — the dictation pipeline still reads MicrophonePermission.status
//  and Paster.isTrusted directly at hotkey time. See
//  docs/superpowers/specs/2026-04-09-onboarding-wire-up-design.md
//  § Non-goals for why the two sources are not unified.
//

import AVFoundation
import AppKit
import ApplicationServices
import Observation

@MainActor
@Observable
final class Permissions {
    // MARK: - Observable state

    /// Current mic authorization, snapshotted from AVFoundation.
    /// Refreshed on init, after `requestMicrophone()`, and by the
    /// monitoring task while the onboarding window is visible.
    private(set) var microphoneStatus: AVAuthorizationStatus

    /// Whether the process is currently trusted for Accessibility.
    /// AX does not expose a "denied" state — only trusted / not.
    private(set) var accessibilityStatus: Bool

    // MARK: - Computed

    var microphoneGranted: Bool { microphoneStatus == .authorized }
    var accessibilityGranted: Bool { accessibilityStatus }

    /// Gate for launch-time onboarding logic and for `GetStartedView`'s
    /// "all green" footer button.
    var allPermissionsGranted: Bool {
        microphoneGranted && accessibilityGranted
    }

    // MARK: - Init

    init() {
        self.microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        self.accessibilityStatus = AXIsProcessTrusted()
    }

    // MARK: - Microphone

    /// Requests mic access if not yet determined, otherwise opens the
    /// relevant System Settings pane so the user can flip it manually.
    /// Always refreshes `microphoneStatus` at the end.
    func requestMicrophone() async {
        let current = AVCaptureDevice.authorizationStatus(for: .audio)

        switch current {
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            microphoneStatus = granted ? .authorized : .denied
        case .denied, .restricted:
            openMicrophoneSettings()
            microphoneStatus = current
        case .authorized:
            microphoneStatus = .authorized
        @unknown default:
            microphoneStatus = current
        }
    }

    func refreshMicrophoneStatus() {
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }

    func openMicrophoneSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Accessibility

    func refreshAccessibilityStatus() {
        accessibilityStatus = AXIsProcessTrusted()
    }

    /// Shows the system prompt that adds Ora to the Accessibility list
    /// in System Settings. Safe to call repeatedly — the system only
    /// surfaces the prompt if not already trusted.
    ///
    /// On macOS Sonoma+ this API became unreliable: the system dialog
    /// frequently does not appear, especially for ad-hoc signed dev
    /// builds or after a previous TCC reset. The side effect of adding
    /// Ora to the Accessibility list still happens, but the user has
    /// no visible signal anything occurred. Prefer `requestAccessibility()`
    /// from UI code paths — it pairs this call with an explicit
    /// settings-pane open so the click is always observable.
    func promptAccessibilityIfNeeded() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options = [key: true] as CFDictionary
        accessibilityStatus = AXIsProcessTrustedWithOptions(options)
    }

    /// High-level "make accessibility happen" entry point for UI code.
    /// Idempotent if already granted. Otherwise: seeds the TCC entry
    /// (so Ora appears in the Accessibility list) AND opens System
    /// Settings to the Accessibility pane so the user sees where to
    /// flip the toggle. Mirrors `requestMicrophone`'s contract of
    /// "click does something visible."
    func requestAccessibility() {
        if accessibilityGranted { return }
        promptAccessibilityIfNeeded()
        if !accessibilityGranted {
            openAccessibilitySettings()
        }
    }

    func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Monitoring

    @ObservationIgnored
    private var monitoringTask: Task<Void, Never>?

    /// Starts polling both permission statuses at the given interval.
    /// Idempotent — calling twice is a no-op. Call `stopMonitoring()`
    /// to tear it down. Intended lifetime: `onAppear`/`onDisappear` of
    /// the onboarding window.
    func startMonitoring(interval: Duration = .milliseconds(500)) {
        guard monitoringTask == nil else { return }
        monitoringTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { break }
                self.refreshMicrophoneStatus()
                self.refreshAccessibilityStatus()
            }
        }
    }

    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }
}
