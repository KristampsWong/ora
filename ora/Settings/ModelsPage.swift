//
//  ModelsPage.swift
//  ora
//
//  Models page — browser for local + API transcription models.
//  No backend wiring: mock model list, local @State, no real downloads.
//

import SwiftUI

// MARK: - Filter

private enum ModelFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case local = "Local"
    case api = "API"
   

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: "square.grid.2x2"
        case .local: "desktopcomputer"
        case .api: "chevron.left.forwardslash.chevron.right"
       
        }
    }
}

// MARK: - Mock Model

struct ModelEntry: Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let badge: String?
    let accuracy: Int
    let speed: Int
    let size: String
    let language: String
    let isLocal: Bool
    let isOnline: Bool
    var status: Status

    enum Status: Equatable {
        case downloaded
        case notDownloaded
        case downloading(progress: Double)
        case paused(progress: Double)
        case extracting
        case error(message: String)
    }
}

// MARK: - Main View

struct ModelsPage: View {
    @State private var selectedFilter: ModelFilter = .local
    @State private var selectedModelId: String? = "parakeet-v3"
    @State private var hoveringCardId: String?
    @State private var removeConfirmId: String?
    @State private var models: [ModelEntry] = ModelManager.mockModels

    private var filteredModels: [ModelEntry] {
        switch selectedFilter {
        case .all: models
        case .local: models.filter(\.isLocal)
        case .api: models.filter(\.isOnline)
        }
    }

    private var localModels: [ModelEntry] {
        filteredModels.filter(\.isLocal)
    }

    private var apiModels: [ModelEntry] {
        filteredModels.filter { !$0.isLocal }
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                // Filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ModelFilter.allCases) { filter in
                            filterChip(filter)
                        }
                    }
                    .padding(.horizontal, 20)
                }

                // Grouped model lists
                VStack(alignment: .leading, spacing: 18) {
                    if !localModels.isEmpty {
                        modelGroup(title: "Local Models", entries: localModels) { model in
                            if let index = models.firstIndex(where: { $0.id == model.id }) {
                                LocalModelCard(
                                    model: $models[index],
                                    selectedModelId: $selectedModelId,
                                    hoveringCardId: $hoveringCardId,
                                    removeConfirmId: $removeConfirmId,
                                    onRemoved: { handleRemoved(model.id) }
                                )
                            }
                        }
                    }
                    if !apiModels.isEmpty {
                        modelGroup(title: "API Models", entries: apiModels) { model in
                            APIModelCard(
                                model: model,
                                selectedModelId: $selectedModelId
                            )
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Model Group

    private func modelGroup<Card: View>(
        title: String,
        entries: [ModelEntry],
        @ViewBuilder card: @escaping (ModelEntry) -> Card
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 10) {
                ForEach(entries) { model in
                    card(model)
                }
            }
        }
    }

    // MARK: - Filter Chip

    private func filterChip(_ filter: ModelFilter) -> some View {
        let isSelected = selectedFilter == filter
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedFilter = filter
            }
        } label: {
            Label(filter.rawValue, systemImage: filter.icon)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.blue.opacity(0.15) : Color.clear)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? Color.blue : Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .foregroundStyle(isSelected ? .blue : .primary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selection bookkeeping

    /// Card-local handlers update model status themselves; the page only needs
    /// to know when to drop a stale selection and pick a fallback.
    private func handleRemoved(_ id: String) {
        guard selectedModelId == id else { return }
        selectedModelId = models.first(where: {
            if case .downloaded = $0.status { return $0.isLocal && $0.id != id }
            return false
        })?.id
    }

}

#Preview {
    ModelsPage()
        .frame(width: 540, height: 600)
}
