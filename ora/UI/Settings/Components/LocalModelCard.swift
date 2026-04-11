//
//  LocalModelCard.swift
//  ora
//
//  Card UI for a locally-runnable transcription model.
//

import SwiftUI

struct LocalModelCard: View {
    let model: ModelEntry
    @Binding var selectedModelId: String?
    @Binding var hoveringCardId: String?
    @Binding var removeConfirmId: String?
    @Environment(ModelManager.self) private var modelManager

    /// Notifies the parent that this model was just removed, so it can clear
    /// `selectedModelId` if it was pointing here. The catalog has already
    /// been updated by `ModelManager` when this fires; if `remove` threw,
    /// this callback does NOT fire.
    var onRemoved: () -> Void = {}

    private var isSelected: Bool { selectedModelId == model.id }

    var body: some View {
        // Three top-level columns: [eye icon] [content] [download control].
        // The content VStack is greedy (`frame(maxWidth: .infinity)`) so the
        // download control is pushed to the trailing edge. Splitting the
        // download control into its own column — instead of nesting it in
        // the content header — means its caption text (e.g. "2m30s") can
        // grow vertically without pushing the description or chips down.
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let asset = model.brandIconAsset {
                    Image(asset)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "eye")
                                .font(.system(size: 14))
                                .foregroundStyle(.green)
                        )
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(model.name)
                    .font(.system(size: 13, weight: .semibold))

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
            .frame(maxWidth: .infinity, alignment: .leading)

            downloadControl
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

        // VStack so the ETA caption can sit directly below the icon. The
        // outer HStack containing this view aligns its children to `.top`,
        // so the icon stays in line with the model name and the caption
        // simply hangs off the bottom of the row — no overlap with the
        // description text below.
        VStack(alignment: .trailing, spacing: 2) {
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

            case .downloading(let eta):
                Button { handlePause() } label: {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: size))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .frame(width: size, height: size)
                // Render the caption only once we have a real ETA. Showing
                // "Downloading" / "…" while waiting for the first sample
                // would force the column wide and then snap narrower, which
                // looks worse than just leaving the slot empty for ~2 s.
                if let caption = Self.downloadingCaption(eta: eta) {
                    captionLabel(text: caption)
                }

            case .paused:
                Button { handleResume() } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: size))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .frame(width: size, height: size)
                captionLabel(text: "Paused")

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
    }

    private func captionLabel(text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    /// Formats an ETA into the compact form the user picked. Returns nil
    /// when there's no estimate yet (the caller skips rendering the
    /// caption entirely in that case — see the `.downloading` branch in
    /// `downloadControl` for why).
    ///
    ///   - nil            — no estimate yet, or speed has stalled
    ///   - "<3s"          — almost done
    ///   - "30s"          — under a minute
    ///   - "2m30s" / "5m" — under an hour, seconds dropped when zero
    ///   - "1h2m" / "1h"  — pathological long downloads
    private static func downloadingCaption(eta: TimeInterval?) -> String? {
        guard let eta else { return nil }
        let total = Int(eta.rounded())
        if total < 3 { return "<3s" }
        if total < 60 { return "\(total)s" }
        let minutes = total / 60
        let seconds = total % 60
        if minutes < 60 {
            return seconds == 0 ? "\(minutes)m" : "\(minutes)m\(seconds)s"
        }
        let hours = minutes / 60
        let mins = minutes % 60
        return mins == 0 ? "\(hours)h" : "\(hours)h\(mins)m"
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

    // MARK: - Actions

    private func handleDownload() {
        modelManager.download(model.id)
    }

    private func handlePause() {
        modelManager.cancel(model.id)
    }

    private func handleResume() {
        modelManager.download(model.id)
    }

    private func handleRemove() {
        do {
            try modelManager.remove(model.id)
            onRemoved()
        } catch {
            // v1: swallow the error per spec (remove failures are rare;
            // the on-disk state recovers on next app launch). Critically,
            // do NOT fire onRemoved() — the model is still .downloaded
            // and the parent must not clear selectedModelId.
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
