//
//  GeneralPage.swift
//  ora
//
//  General settings page — UI-only port from WhisperIsland, now with
//  Sparkle-backed "Check for Updates…" wired into the Other section.
//

import SwiftUI

struct GeneralPage: View {
    @Environment(Preferences.self) private var preferences
    @StateObject private var updateController = UpdateController.shared
    @State private var appearance: String = "System"
    @State private var notificationSound: String = "Pop"
    @State private var notificationSoundEnabled: Bool = true
    @State private var localOnlyMode: Bool = false

    private let notificationSounds = ["Pop", "Tink", "Glass", "Hero"]

    var body: some View {
        @Bindable var preferences = preferences
        // Safety rail: don't let the user hide both the dock icon and the
        // status bar item at the same time, or the app becomes unreachable.
        let dockToggleLocked = preferences.showInDock && !preferences.showInStatusBar
        let statusToggleLocked = preferences.showInStatusBar && !preferences.showInDock
        return Form {
            Section("Interface") {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("System")
                    Text("Dark").tag("Dark")
                    Text("Light").tag("Light")
                }
            }

            Section("Behavior") {
                Toggle("Show in Dock", isOn: $preferences.showInDock)
                    .disabled(dockToggleLocked)

                Toggle("Show in status bar", isOn: $preferences.showInStatusBar)
                    .disabled(statusToggleLocked)

                Toggle("Launch at login", isOn: $preferences.launchAtLogin)
            }

            Section("Notifications") {
                Toggle("Play sound", isOn: $notificationSoundEnabled)

                Picker("Sound", selection: $notificationSound) {
                    ForEach(notificationSounds, id: \.self) { sound in
                        Text(sound).tag(sound)
                    }
                }
                .disabled(!notificationSoundEnabled)
            }

            Section {
                Toggle("Local mode only", isOn: $localOnlyMode)
                    .disabled(true)
            }

            Section("Other") {
                LabeledContent("Updates") {
                    Button("Check for Updates…") {
                        updateController.checkForUpdates()
                    }
                    .disabled(!updateController.canCheckForUpdates)
                }
                LabeledContent("Installed", value: versionString)
            }
        }
        .formStyle(.grouped)
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }
}

#Preview {
    GeneralPage()
        .frame(width: 500, height: 600)
}
