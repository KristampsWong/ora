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
    @Environment(InputDeviceStore.self) private var inputDevices

    var body: some View {
        // Refresh the device list on every menu-open. MenuBarExtra(.menu)
        // re-evaluates this body each time the dropdown is opened, and
        // SwiftUI's `.onAppear` does not fire reliably on NSMenuItem-
        // backed views, so the simplest reliable hook is calling refresh
        // here. `InputDeviceStore.refresh()` is equality-guarded — it
        // only writes to `devices` when the enumeration actually
        // changed — so this doesn't loop via @Observable re-eval.
        let _ = inputDevices.refresh()

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

        // Input source submenu — real HAL enumeration.
        Menu("Input Source") {
            inputSourceMenu
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

    /// Builds the Input Source submenu body. Pulled out so the
    /// `.onAppear` refresh and the conditional checkmark logic stay
    /// readable.
    @ViewBuilder
    private var inputSourceMenu: some View {
        let systemDefaultChecked = InputDeviceStore.isSystemDefaultChecked(
            selectedUID: inputDevices.selectedUID,
            devices: inputDevices.devices
        )

        Button {
            inputDevices.select(uid: nil)
        } label: {
            if systemDefaultChecked {
                Label("System Default", systemImage: "checkmark")
            } else {
                Text("System Default")
            }
        }

        if !inputDevices.devices.isEmpty {
            Divider()
        }

        ForEach(inputDevices.devices) { device in
            Button {
                inputDevices.select(uid: device.uid)
            } label: {
                if device.uid == inputDevices.selectedUID {
                    Label(device.name, systemImage: "checkmark")
                } else {
                    Text(device.name)
                }
            }
        }
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        return "Version \(version)"
    }
}
