//
//  DictationPage.swift
//  ora
//
//  Dictation trigger settings — hotkey and input mode.
//  UI-only: local @State, no real hotkey registration.
//

import SwiftUI

struct DictationPage: View {
    @Environment(Preferences.self) private var preferences
    @State private var activationKey: String = "Right ⌥"
    @State private var inputMode: InputMode = .pushToTalk
    @State private var testInput: String = ""
    @FocusState private var isTestFocused: Bool

    private let activationKeys = [
        "Right ⌥",
        "Right ⌘",
        "Fn",
        "F5",
        "⌃Space",
    ]

    enum InputMode: String, CaseIterable, Identifiable {
        case pushToTalk
        case toggle

        var id: String { rawValue }

        var title: String {
            switch self {
            case .pushToTalk: "Push to Talk"
            case .toggle: "Toggle"
            }
        }

        var description: String {
            switch self {
            case .pushToTalk: "Hold the key to dictate, release to stop."
            case .toggle: "Press once to start, press again to stop."
            }
        }
    }

    var body: some View {
        @Bindable var preferences = preferences
        return Form {
            Section("Output") {
                Toggle("Paste transcript automatically", isOn: $preferences.autoPaste)
            }

            Section("Trigger") {
                Picker("Shortcut", selection: $activationKey) {
                    ForEach(activationKeys, id: \.self) { key in
                        Text(key).tag(key)
                    }
                }

                Picker("Input mode", selection: $inputMode) {
                    ForEach(InputMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(inputMode.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("Try It Out") {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $testInput)
                        .font(.body)
                        .focused($isTestFocused)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 80)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(
                                    isTestFocused ? Color.accentColor : Color(nsColor: .separatorColor),
                                    lineWidth: isTestFocused ? 2 : 1
                                )
                        )

                    if testInput.isEmpty {
                        Text("Hold \(activationKey) and speak to test…")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(12)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    DictationPage()
        .frame(width: 500, height: 400)
}
