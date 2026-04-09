//
//  oraApp.swift
//  ora
//
//  Created by Kristamps Wang on 4/8/26.
//

import SwiftUI

@main
struct oraApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)

        MenuBarExtra("Ora", systemImage: "waveform") {
            MenuBarView()
        }
        .menuBarExtraStyle(.menu)
    }
}
