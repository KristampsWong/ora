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

private struct ModelEntry: Identifiable, Equatable {
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
    @State private var models: [ModelEntry] = ModelsPage.mockModels

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
                        modelGroup(title: "Local Models", entries: localModels)
                    }
                    if !apiModels.isEmpty {
                        modelGroup(title: "API Models", entries: apiModels)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Model Group

    private func modelGroup(title: String, entries: [ModelEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 10) {
                ForEach(entries) { model in
                    modelCard(model)
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

    // MARK: - Model Card

    private func modelCard(_ model: ModelEntry) -> some View {
        let isSelected = selectedModelId == model.id

        return HStack(alignment: .top, spacing: 10) {
            // Icon
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: model.isLocal ? "eye" : "cloud.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(model.isLocal ? .green : .blue)
                )

            VStack(alignment: .leading, spacing: 6) {
                // Name + badge + status control
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(.system(size: 13, weight: .semibold))

                    if model.isLocal, let badge = model.badge {
                        Text(badge)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }

                    Spacer()

                    if model.isLocal {
                        downloadControl(model)
                    } else {
                        settingsButton(model)
                    }
                }

                // Description
                Text(model.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // Attribute chips (local only)
                if model.isLocal {
                    ChipFlowLayout(spacing: 3) {
                        ratingChip("scope", filled: model.accuracy, total: 5)
                        ratingChip("bolt.fill", filled: model.speed, total: 5)
                        attributeChip("internaldrive", model.size)
                        attributeChip("globe", model.language)
                        attributeChip("desktopcomputer", "Local")
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected
                      ? Color.blue.opacity(0.08)
                      : Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isSelected ? Color.blue : Color.secondary.opacity(0.15),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveringCardId = hovering ? model.id : nil
            }
        }
        .onTapGesture {
            if case .downloaded = model.status {
                selectedModelId = model.id
            }
        }
        .alert("Remove Model",
               isPresented: Binding(
                   get: { removeConfirmId == model.id },
                   set: { if !$0 { removeConfirmId = nil } }
               )
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                handleRemove(model.id)
            }
        } message: {
            Text("Are you sure you want to remove \"\(model.name)\"? You can download it again later.")
        }
    }

    // MARK: - Settings Button (cloud / API models)

    private func settingsButton(_ model: ModelEntry) -> some View {
        Button {
            // TODO: open API settings sheet (key, endpoint, etc.)
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .frame(width: 16, height: 16)
    }

    // MARK: - Download Control (App Store Style)

    @ViewBuilder
    private func downloadControl(_ model: ModelEntry) -> some View {
        let size: CGFloat = 16

        switch model.status {
        case .downloaded:
            if hoveringCardId == model.id && model.isLocal {
                Button { removeConfirmId = model.id } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: size))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: size, height: size)
            }

        case .notDownloaded:
            Button { handleDownload(model.id) } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: size))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .frame(width: size, height: size)

        case .downloading(let progress):
            Button { handlePause(model.id) } label: {
                circularProgress(progress: progress, icon: "pause.fill", size: size)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

        case .paused(let progress):
            Button { handleResume(model.id) } label: {
                circularProgress(progress: progress, icon: "arrow.down", size: size)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

        case .extracting:
            SpinningCircle(size: size)
                .frame(width: size, height: size)

        case .error(let message):
            Button { handleDownload(model.id) } label: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: size))
                    .foregroundStyle(.red)
                    .help(message)
            }
            .buttonStyle(.plain)
            .frame(width: size, height: size)
        }
    }

    private func circularProgress(progress: Double, icon: String, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1.5)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Image(systemName: icon)
                .font(.system(size: size * 0.35, weight: .bold))
                .foregroundStyle(.blue)
        }
        .frame(width: size, height: size)
    }

    // MARK: - Attribute Chip

    private func chipContainer<Content: View>(_ icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
            content()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .foregroundStyle(.secondary)
    }

    private func attributeChip(_ icon: String, _ text: String, textSize: CGFloat = 10) -> some View {
        chipContainer(icon) {
            Text(text)
                .font(.system(size: textSize, weight: .medium))
        }
    }

    private func ratingChip(_ icon: String, filled: Int, total: Int) -> some View {
        let dotSize: CGFloat = 5
        return chipContainer(icon) {
            HStack(spacing: 2) {
                ForEach(0..<total, id: \.self) { i in
                    Circle()
                        .fill(i < filled ? Color.secondary : Color.secondary.opacity(0.3))
                        .frame(width: dotSize, height: dotSize)
                }
            }
        }
    }

    // MARK: - Actions (UI-only mock)

    private func handleDownload(_ id: String) {
        startDownloading(id)
    }

    private func handlePause(_ id: String) {
        guard let index = models.firstIndex(where: { $0.id == id }) else { return }
        if case .downloading(let p) = models[index].status {
            withAnimation(.easeInOut(duration: 0.15)) {
                models[index].status = .paused(progress: p)
            }
        }
    }

    private func handleResume(_ id: String) {
        startDownloading(id)
    }

    /// Simulated downloader: ticks progress every 100ms until 1.0,
    /// then briefly enters .extracting before settling to .downloaded.
    /// Exits early if the status leaves .downloading (e.g., user paused).
    private func startDownloading(_ id: String) {
        guard let index = models.firstIndex(where: { $0.id == id }) else { return }

        let startProgress: Double
        switch models[index].status {
        case .paused(let p): startProgress = p
        case .downloading(let p): startProgress = p
        default: startProgress = 0.0
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            models[index].status = .downloading(progress: startProgress)
        }

        Task { @MainActor in
            var progress = startProgress
            let increment = 0.025

            while progress < 1.0 {
                try? await Task.sleep(for: .milliseconds(100))

                guard let i = models.firstIndex(where: { $0.id == id }),
                      case .downloading = models[i].status else {
                    return // paused or removed
                }

                progress = min(1.0, progress + increment)
                withAnimation(.linear(duration: 0.1)) {
                    models[i].status = .downloading(progress: progress)
                }
            }

            // Brief extracting state
            guard let i = models.firstIndex(where: { $0.id == id }),
                  case .downloading = models[i].status else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                models[i].status = .extracting
            }
            try? await Task.sleep(for: .milliseconds(600))

            // Settle to downloaded
            guard let j = models.firstIndex(where: { $0.id == id }),
                  case .extracting = models[j].status else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                models[j].status = .downloaded
            }
        }
    }

    private func handleRemove(_ id: String) {
        guard let index = models.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            models[index].status = .notDownloaded
        }
        if selectedModelId == id {
            selectedModelId = models.first(where: {
                if case .downloaded = $0.status { return $0.isLocal && $0.id != id }
                return false
            })?.id
        }
    }

    // MARK: - Mock Data

    private static let mockModels: [ModelEntry] = [
        ModelEntry(
            id: "parakeet-v3",
            name: "Nvidia Parakeet Tdt 0.6B V3",
            description: "Ultra-fast transcription powered by NVIDIA FastConformer. Optimized for conversational speech and voice commands.",
            badge: "Best for Multilingual",
            accuracy: 5,
            speed: 5,
            size: "496 MB",
            language: "Multilingual",
            isLocal: true,
            isOnline: false,
            status: .downloaded
        ),
        ModelEntry(
            id: "parakeet-v2",
            name: "Nvidia Parakeet Tdt 0.6B V2",
            description: "Ultra-fast English-only transcription powered by NVIDIA FastConformer V2. Optimized for English dictation and voice commands.",
            badge: "Best for English",
            accuracy: 5,
            speed: 5,
            size: "490 MB",
            language: "English",
            isLocal: true,
            isOnline: false,
            status: .notDownloaded
        ),
        ModelEntry(
            id: "gpt-4o-transcribe",
            name: "GPT-4o Transcribe",
            description: "State-of-the-art cloud transcription powered by GPT-4o. Highest accuracy available.",
            badge: "Best Cloud",
            accuracy: 5,
            speed: 4,
            size: "$0.006/min",
            language: "Multilingual",
            isLocal: false,
            isOnline: true,
            status: .downloaded
        ),
        ModelEntry(
            id: "whisper-1-api",
            name: "Whisper-1 API",
            description: "Cloud-hosted Whisper model via OpenAI API. No local compute required.",
            badge: nil,
            accuracy: 4,
            speed: 4,
            size: "$0.006/min",
            language: "Multilingual",
            isLocal: false,
            isOnline: true,
            status: .downloaded
        ),
    ]
}

// MARK: - Spinner

private struct SpinningCircle: View {
    let size: CGFloat
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(Color.blue, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

// MARK: - Chip Flow Layout

private struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(in: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(in: bounds.width, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(in maxWidth: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}

#Preview {
    ModelsPage()
        .frame(width: 540, height: 600)
}
