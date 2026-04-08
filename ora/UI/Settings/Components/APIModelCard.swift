//
//  APIModelCard.swift
//  ora
//
//  Card UI for a cloud / API-based transcription model.
//

import SwiftUI

struct APIModelCard: View {
    let model: ModelEntry
    @Binding var selectedModelId: String?

    @State private var isSettingsPresented = false

    private var isSelected: Bool { selectedModelId == model.id }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.blue)
                )

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(.system(size: 13, weight: .semibold))

                    Spacer()

                    settingsButton
                }

                Text(model.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(ModelCardChrome.background(isSelected: isSelected))
        .overlay(ModelCardChrome.border(isSelected: isSelected))
        .contentShape(Rectangle())
        .onTapGesture {
            if case .downloaded = model.status {
                selectedModelId = model.id
            }
        }
    }

    // MARK: - Settings Button

    private var settingsButton: some View {
        Button {
            isSettingsPresented = true
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .frame(width: 11, height: 11)
        .sheet(isPresented: $isSettingsPresented) {
            APISettingsSheet(providerId: model.id, providerName: model.name)
        }
    }
}

// MARK: - API Settings Sheet

private struct APISettingsSheet: View {
    let providerId: String
    let providerName: String

    @Environment(\.dismiss) private var dismiss
    @AppStorage private var apiKey: String
    @AppStorage private var selectedModel: String

    init(providerId: String, providerName: String) {
        self.providerId = providerId
        self.providerName = providerName
        // TODO: migrate apiKey to Keychain — AppStorage is plaintext UserDefaults.
        _apiKey = AppStorage(wrappedValue: "", "api.\(providerId).key")
        _selectedModel = AppStorage(wrappedValue: "", "api.\(providerId).model")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("\(providerName) Settings")
                .font(.system(size: 15, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("API Key")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                SecureField("sk-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Model")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField(Self.modelPlaceholder(for: providerId), text: $selectedModel)
                    .textFieldStyle(.roundedBorder)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360, height: 240)
    }

    private static func modelPlaceholder(for providerId: String) -> String {
        switch providerId {
        case "openai-api": "e.g. gpt-4o-transcribe"
        case "groq-api": "e.g. whisper-large-v3"
        default: "Model name"
        }
    }
}

// MARK: - Shared Card Chrome

enum ModelCardChrome {
    static func background(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(isSelected
                  ? Color.blue.opacity(0.08)
                  : Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    static func border(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(
                isSelected ? Color.blue : Color.secondary.opacity(0.15),
                lineWidth: isSelected ? 1.5 : 0.5
            )
    }
}
