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
}
