//
//  MenuBarView.swift
//  ora
//
//  Menu bar dropdown — native NSMenu style.
//  Hosted by a MenuBarExtra(.menu) so each Button/Menu/Divider here
//  becomes a real NSMenuItem rather than a custom popover row.
//

import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var selectedInputName = "MacBook Pro Microphone"

    private static let mockInputDevices = [
        "MacBook Pro Microphone",
        "AirPods Pro",
        "External USB Mic",
    ]

    var body: some View {
        // Settings pages — sourced from SettingsPage.allCases so the
        // sidebar and menu stay in sync automatically.
        ForEach(SettingsPage.allCases) { page in
            Button {
                // Set the navigator BEFORE openWindow so ContentView's
                // .onAppear/.onChange picks it up on the way up. This
                // is the same race-free pattern OnboardingWindowContent
                // uses — see SettingsNavigator's header for the why.
                SettingsNavigator.shared.pendingPage = page
                openWindow(id: "settings")
            } label: {
                Label(page.title, systemImage: page.icon)
            }
        }

        Divider()

        // Input source submenu
        Menu("Input Source") {
            ForEach(Self.mockInputDevices, id: \.self) { device in
                Button {
                    selectedInputName = device
                } label: {
                    if device == selectedInputName {
                        Label(device, systemImage: "checkmark")
                    } else {
                        Text(device)
                    }
                }
            }
        }

        Divider()

        Text(versionString)

        Button("Check for Updates") {
            // TODO: wire to update checker.
        }

        Divider()

        Button("Quit Ora") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        return "Version \(version)"
    }
}
