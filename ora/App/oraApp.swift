//
//  oraApp.swift
//  ora
//
//  Created by Kristamps Wang on 4/8/26.
//

import SwiftUI

@main
struct oraApp: App {
    @State private var preferences: Preferences

    init() {
        let prefs = Preferences.shared
        _preferences = State(initialValue: prefs)
        // Defer the first apply to the next runloop turn: applying the dock
        // activation policy synchronously in App.init() runs before AppKit has
        // finished its own launch sequence, and AppKit will then clobber our
        // .accessory policy back to .regular when it sees the WindowGroup.
        // Running one tick later lets the policy stick.
        DispatchQueue.main.async {
            AppearanceController.apply(prefs)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(preferences)
                .onChange(of: preferences.showInDock) { _, newValue in
                    AppearanceController.applyDockVisibility(newValue)
                }
                .onChange(of: preferences.launchAtLogin) { _, newValue in
                    AppearanceController.applyLaunchAtLogin(newValue)
                }
        }
        .windowResizability(.contentSize)

        MenuBarExtra(
            "Ora",
            systemImage: "waveform",
            isInserted: Binding(
                get: { preferences.showInStatusBar },
                set: { preferences.showInStatusBar = $0 }
            )
        ) {
            MenuBarView()
                .environment(preferences)
        }
        .menuBarExtraStyle(.menu)
    }
}
