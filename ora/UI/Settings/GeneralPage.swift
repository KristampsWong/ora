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

    var body: some View {
        @Bindable var preferences = preferences
        // Safety rail: don't let the user hide both the dock icon and the
        // status bar item at the same time, or the app becomes unreachable.
        let dockToggleLocked = preferences.showInDock && !preferences.showInStatusBar
        let statusToggleLocked = preferences.showInStatusBar && !preferences.showInDock
        return Form {
            Section("Interface") {
                Picker("Appearance", selection: $preferences.appearance) {
                    Text("System").tag(AppearanceMode.system)
                    Text("Light").tag(AppearanceMode.light)
                    Text("Dark").tag(AppearanceMode.dark)
                }
            }

            Section("Behavior") {
                Toggle("Show in Dock", isOn: $preferences.showInDock)
                    .disabled(dockToggleLocked)

                Toggle("Show in status bar", isOn: $preferences.showInStatusBar)
                    .disabled(statusToggleLocked)

                Toggle("Launch at login", isOn: $preferences.launchAtLogin)
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
        #if DEBUG
        return "\(BuildInfo.marketingVersion)-dev (\(BuildInfo.gitCommitHash))"
        #else
        return "\(BuildInfo.marketingVersion) (\(BuildInfo.gitCommitHash))"
        #endif
    }
}

#Preview {
    GeneralPage()
        .frame(width: 500, height: 600)
}
