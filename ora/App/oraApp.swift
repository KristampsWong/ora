//
//  oraApp.swift
//  ora
//
//  Created by Kristamps Wang on 4/8/26.
//

import AppKit
import SwiftUI

@main
struct oraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var preferences = Preferences.shared
    @State private var modelManager = ModelManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(preferences)
                .environment(modelManager)
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
                .environment(modelManager)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Menu-bar-first app delegate.
///
/// The real "no dock icon at launch" guarantee comes from
/// `INFOPLIST_KEY_LSUIElement = YES` in the target's build settings — with
/// that flag the app launches as an agent and the dock never knows about
/// it in the first place, so there's no flash to hide. This delegate then
/// reads the user's `Show in Dock` preference and promotes the activation
/// policy to `.regular` if they've opted in.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Owned here because the registration lifetime should match the
    /// process lifetime — the hotkey needs to survive window open/close
    /// cycles and settings sheet presentations. Retained strongly;
    /// deinit of `HotkeyService` tears down the Carbon registration.
    private let hotkeyService = HotkeyService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppearanceController.apply(Preferences.shared)

        // M4: register the default hotkey and log press/release so we
        // can verify the global subscription works from other apps.
        // Wiring to the dictation pipeline lands in M6; for now this is
        // a standalone heartbeat.
        hotkeyService.onPress = {
            print("[Hotkey] press")
        }
        hotkeyService.onRelease = {
            print("[Hotkey] release")
        }
        hotkeyService.register(.optionSpace)
    }

    /// Don't quit when the last window closes — we live in the menu bar,
    /// and closing the Settings window should hide it, not kill the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
