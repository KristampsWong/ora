//
//  SettingsPage.swift
//  ora
//
//  Enum of pages shown in the settings navigation bar.
//

import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case models
    case general
    case dictation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .dictation: "Dictation"
        case .models: "Models"
        }
    }

    var icon: String {
        switch self {
        case .general: "gear"
        case .dictation: "mic"
        case .models: "sparkle"
        }
    }
}

extension Notification.Name {
    /// Posted when something wants the Settings window to jump to a
    /// specific page. The notification's `object` is the target
    /// `SettingsPage`. `ContentView` subscribes and updates its
    /// `selection` when it receives one.
    static let oraOpenSettingsPage = Notification.Name("ora.openSettingsPage")
}
