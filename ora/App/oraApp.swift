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
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The dictation pipeline. Created at launch; owns hotkey, recorder,
    /// transcriber, paster, and the overlay controller. The coordinator's
    /// lifetime is the process's lifetime — Carbon hotkey registration
    /// and the FluidAudio model load are both kept alive across window
    /// open/close cycles.
    private var coordinator: DictationCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppearanceController.apply(Preferences.shared)

        let coordinator = DictationCoordinator()
        coordinator.start()
        self.coordinator = coordinator
    }

    /// Don't quit when the last window closes — we live in the menu bar,
    /// and closing the Settings window should hide it, not kill the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
