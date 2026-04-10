//
//  DictationPage.swift
//  ora
//
//  Dictation trigger settings — hotkey shortcut and input mode.
//

import SwiftUI

struct DictationPage: View {
    @Environment(Preferences.self) private var preferences
    @State private var inputMode: InputMode = .pushToTalk
    @State private var testInput: String = ""
    @FocusState private var isTestFocused: Bool

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
                Picker("Shortcut", selection: $preferences.activationKey) {
                    ForEach(ActivationKey.allCases) { key in
                        Text(key.rawValue).tag(key)
                    }
                }
                .onChange(of: preferences.activationKey) { _, _ in
                    DictationCoordinator.shared.updateHotkey()
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
                        Text("Hold \(preferences.activationKey.rawValue) and speak to test…")
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
        .environment(Preferences.shared)
        .frame(width: 500, height: 400)
}
