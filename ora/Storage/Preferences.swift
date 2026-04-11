//
//  Preferences.swift
//  ora
//
//  Persistent user preferences, backed by UserDefaults.
//  Observed by SwiftUI via @Observable; mutations flow straight to defaults
//  so every setting survives an app quit-and-relaunch.
//

import Foundation
import Observation

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
}

@Observable
final class Preferences {
    static let shared = Preferences()

    private enum Key {
        static let selectedModelId = "ora.selectedModelId"
        static let autoPaste = "ora.autoPaste"
        static let hasCompletedOnboarding = "ora.hasCompletedOnboarding"
        static let showInDock = "ora.showInDock"
        static let showInStatusBar = "ora.showInStatusBar"
        static let launchAtLogin = "ora.launchAtLogin"
        static let activationKey = "ora.activationKey"
        static let appearance = "ora.appearance"
        static let notificationSoundEnabled = "ora.notificationSoundEnabled"
        static let notificationSoundName = "ora.notificationSoundName"
        static let selectedInputDeviceUID = "ora.selectedInputDeviceUID"
    }

    private let defaults: UserDefaults

    var selectedModelId: String? {
        didSet { defaults.set(selectedModelId, forKey: Key.selectedModelId) }
    }

    var autoPaste: Bool {
        didSet { defaults.set(autoPaste, forKey: Key.autoPaste) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    var showInDock: Bool {
        didSet { defaults.set(showInDock, forKey: Key.showInDock) }
    }

    var showInStatusBar: Bool {
        didSet { defaults.set(showInStatusBar, forKey: Key.showInStatusBar) }
    }

    var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    var activationKey: ActivationKey {
        didSet { defaults.set(activationKey.rawValue, forKey: Key.activationKey) }
    }

    var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    var notificationSoundEnabled: Bool {
        didSet { defaults.set(notificationSoundEnabled, forKey: Key.notificationSoundEnabled) }
    }

    var notificationSoundName: String {
        didSet { defaults.set(notificationSoundName, forKey: Key.notificationSoundName) }
    }

    /// UID of the input device the user pinned for dictation. `nil`
    /// means "Follow System Default" — the recorder uses whatever the
    /// system default input is at record time. Stable across reboots
    /// and reconnects (HAL `kAudioDevicePropertyDeviceUID`).
    var selectedInputDeviceUID: String? {
        didSet {
            if let selectedInputDeviceUID {
                defaults.set(selectedInputDeviceUID, forKey: Key.selectedInputDeviceUID)
            } else {
                defaults.removeObject(forKey: Key.selectedInputDeviceUID)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.selectedModelId = defaults.string(forKey: Key.selectedModelId) ?? "parakeet-v3"
        self.autoPaste = (defaults.object(forKey: Key.autoPaste) as? Bool) ?? true
        self.hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        self.showInDock = (defaults.object(forKey: Key.showInDock) as? Bool) ?? false
        self.showInStatusBar = (defaults.object(forKey: Key.showInStatusBar) as? Bool) ?? true
        self.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        if let raw = defaults.string(forKey: Key.activationKey),
           let key = ActivationKey(rawValue: raw) {
            self.activationKey = key
        } else {
            self.activationKey = .default
        }
        if let raw = defaults.string(forKey: Key.appearance),
           let mode = AppearanceMode(rawValue: raw) {
            self.appearance = mode
        } else {
            self.appearance = .system
        }
        self.notificationSoundEnabled = (defaults.object(forKey: Key.notificationSoundEnabled) as? Bool) ?? true
        self.notificationSoundName = defaults.string(forKey: Key.notificationSoundName) ?? "Pop"
        self.selectedInputDeviceUID = defaults.string(forKey: Key.selectedInputDeviceUID)
    }
}
