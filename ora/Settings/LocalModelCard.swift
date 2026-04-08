//
//  LocalModelCard.swift
//  ora
//
//  Card UI for a locally-runnable transcription model.
//

import SwiftUI

struct LocalModelCard: View {
    @Binding var model: ModelEntry
    @Binding var selectedModelId: String?
    @Binding var hoveringCardId: String?
    @Binding var removeConfirmId: String?

    /// Notifies the parent that this model was just removed, so it can clear
    /// `selectedModelId` if it was pointing here. Card-local state is updated
    /// before this fires.
    var onRemoved: () -> Void = {}

    private var isSelected: Bool { selectedModelId == model.id }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "eye")
                        .font(.system(size: 14))
                        .foregroundStyle(.green)
                )

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(.system(size: 13, weight: .semibold))

                    Spacer()

                    downloadControl
                }

                Text(model.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                ChipFlowLayout(spacing: 3) {
                    ratingChip("scope", filled: model.accuracy, total: 5)
                    ratingChip("bolt.fill", filled: model.speed, total: 5)
                    attributeChip("internaldrive", model.size)
                    attributeChip("globe", model.language)
                }
            }
        }
        .padding(12)
        .background(ModelCardChrome.background(isSelected: isSelected))
        .overlay(ModelCardChrome.border(isSelected: isSelected))
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
                handleRemove()
            }
        } message: {
            Text("Are you sure you want to remove \"\(model.name)\"? You can download it again later.")
        }
    }

    // MARK: - Download Control (App Store Style)

    @ViewBuilder
    private var downloadControl: some View {
        let size: CGFloat = 16

        switch model.status {
        case .downloaded:
            if hoveringCardId == model.id {
                Button { removeConfirmId = model.id } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: size))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: size, height: size)
            }

        case .notDownloaded:
            Button { handleDownload() } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: size))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .frame(width: size, height: size)

        case .downloading(let progress):
            Button { handlePause() } label: {
                circularProgress(progress: progress, icon: "pause.fill", size: size)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

        case .paused(let progress):
            Button { handleResume() } label: {
                circularProgress(progress: progress, icon: "arrow.down", size: size)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

        case .extracting:
            SpinningCircle(size: size)
                .frame(width: size, height: size)

        case .error(let message):
            Button { handleDownload() } label: {
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

    // MARK: - Chips

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

    private func handleDownload() {
        startDownloading()
    }

    private func handlePause() {
        if case .downloading(let p) = model.status {
            withAnimation(.easeInOut(duration: 0.15)) {
                model.status = .paused(progress: p)
            }
        }
    }

    private func handleResume() {
        startDownloading()
    }

    private func handleRemove() {
        withAnimation(.easeInOut(duration: 0.15)) {
            model.status = .notDownloaded
        }
        onRemoved()
    }

    /// Simulated downloader: ticks progress every 100ms until 1.0,
    /// then briefly enters .extracting before settling to .downloaded.
    /// Exits early if the status leaves .downloading (e.g., user paused).
    private func startDownloading() {
        let startProgress: Double
        switch model.status {
        case .paused(let p): startProgress = p
        case .downloading(let p): startProgress = p
        default: startProgress = 0.0
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            model.status = .downloading(progress: startProgress)
        }

        let id = model.id
        Task { @MainActor in
            var progress = startProgress
            let increment = 0.025

            while progress < 1.0 {
                try? await Task.sleep(for: .milliseconds(100))

                guard model.id == id, case .downloading = model.status else {
                    return // paused, removed, or model swapped out
                }

                progress = min(1.0, progress + increment)
                withAnimation(.linear(duration: 0.1)) {
                    model.status = .downloading(progress: progress)
                }
            }

            // Brief extracting state
            guard model.id == id, case .downloading = model.status else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                model.status = .extracting
            }
            try? await Task.sleep(for: .milliseconds(600))

            // Settle to downloaded
            guard model.id == id, case .extracting = model.status else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                model.status = .downloaded
            }
        }
    }
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
