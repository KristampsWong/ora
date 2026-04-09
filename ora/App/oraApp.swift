//
//  oraApp.swift
//  ora
//
//  Created by Kristamps Wang on 4/8/26.
//

import SwiftUI

@main
struct oraApp: App {
    @State private var preferences = Preferences.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(preferences)
        }
        .windowResizability(.contentSize)

        MenuBarExtra("Ora", systemImage: "waveform") {
            MenuBarView()
                .environment(preferences)
        }
        .menuBarExtraStyle(.menu)
    }
}
