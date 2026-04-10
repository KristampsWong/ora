//
//  InputDeviceStore.swift
//  ora
//
//  App-wide source of truth for the "which input device should the
//  recorder use?" setting. Enumerates Core Audio HAL input devices,
//  publishes the current list and selected UID, persists the
//  selection via `Preferences`, and resolves UID → ephemeral
//  `AudioDeviceID` at record time.
//
//  ## Why UID is the identity
//
//  `AudioDeviceID` is an unsigned-int handle that Core Audio hands out
//  per enumeration — it can change across device reconnects and
//  sometimes across reboots. `kAudioDevicePropertyDeviceUID` returns
//  a stable `CFString` identity that persists, so we persist THAT and
//  re-resolve to an `AudioDeviceID` every time we need to apply the
//  override.
//
//  ## Silent-fallback policy
//
//  If the persisted UID isn't in the current enumeration (device
//  unplugged), `resolveSelectedDeviceID()` returns `nil` and the
//  recorder falls back to the system default. We don't surface a
//  warning — see the design spec's scope-B decision.
//

import CoreAudio
import Foundation
import Observation

@MainActor
@Observable
final class InputDeviceStore {
    private(set) var devices: [InputDevice] = []
    private(set) var selectedUID: String?

    @ObservationIgnored private let preferences: Preferences

    init(preferences: Preferences) {
        self.preferences = preferences
        self.selectedUID = preferences.selectedInputDeviceUID
    }

    /// Updates the selected UID and persists it. Pass `nil` to fall
    /// back to "Follow System Default".
    func select(uid: String?) {
        selectedUID = uid
        preferences.selectedInputDeviceUID = uid
    }

    /// True when the menu should draw a checkmark next to "System
    /// Default": either nothing is selected, or the persisted UID
    /// doesn't match any currently-enumerated device (stale → we're
    /// effectively following the system default at record time).
    static func isSystemDefaultChecked(selectedUID: String?, devices: [InputDevice]) -> Bool {
        guard let selectedUID else { return true }
        return !devices.contains(where: { $0.uid == selectedUID })
    }

    // MARK: - HAL enumeration

    /// Re-enumerates Core Audio input devices and publishes the
    /// result. Added in a later task.
    func refresh() {
        // Intentionally empty for Task 3 — HAL enumeration lands in
        // Task 4.
    }

    /// Re-enumerates devices and returns the ephemeral `AudioDeviceID`
    /// corresponding to `selectedUID`, or `nil` if `selectedUID` is
    /// unset or unresolvable. Added in a later task.
    func resolveSelectedDeviceID() -> AudioDeviceID? {
        // Intentionally returns nil for Task 3 — HAL enumeration
        // lands in Task 4.
        return nil
    }
}
