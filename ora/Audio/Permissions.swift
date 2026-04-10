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
    func promptAccessibilityIfNeeded() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options = [key: true] as CFDictionary
        accessibilityStatus = AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
