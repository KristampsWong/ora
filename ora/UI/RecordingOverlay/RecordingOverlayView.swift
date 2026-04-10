//
//  RecordingOverlayView.swift
//  ora
//
//  Floating "pill" overlay shown during dictation. Ported from the
//  prior whisper project. Three visual modes:
//
//   - Recording: animated waveform driven by `state.audioLevel` (0...1)
//   - Transcribing / initializing: 3-dot breathing indicator
//   - Error: icon + short text in a colored pill (red for permission
//     errors, orange for generic)
//
//  The view is a pure binding to `RecordingOverlayState` — it has no
//  control logic. The `RecordingOverlayController` owns the NSPanel
//  and drives the state.
//

import SwiftUI

// MARK: - State

enum OverlayPhase: Equatable {
    case initializing           // unused by DictationCoordinator, kept for future
    case recording
    case transcribing
    case done                   // set by RecordingOverlayController.hide() as housekeeping
    case errorNoMic
    case errorNoAccessibility
    case errorNoModel
    case errorNoSpeech
    case errorGeneric(String)
}

enum RecordingTriggerMode {
    case hold
}

@Observable
final class RecordingOverlayState {
    var phase: OverlayPhase = .recording
    var audioLevel: Float = 0.0
    var triggerMode: RecordingTriggerMode = .hold
}

// MARK: - Waveform

struct WaveformBar: View {
    let amplitude: CGFloat

    private let minHeight: CGFloat = 2
    private let maxHeight: CGFloat = 20

    var body: some View {
        Capsule()
            .fill(.white)
            .frame(width: 3, height: minHeight + (maxHeight - minHeight) * amplitude)
    }
}

struct WaveformView: View {
    let audioLevel: Float

    private static let barCount = 9
    private static let multipliers: [CGFloat] = [0.35, 0.55, 0.75, 0.9, 1.0, 0.9, 0.75, 0.55, 0.35]

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                WaveformBar(amplitude: barAmplitude(for: index))
                    .animation(
                        .interpolatingSpring(stiffness: 600, damping: 28),
                        value: audioLevel
                    )
            }
        }
        .frame(height: 20)
    }

    private func barAmplitude(for index: Int) -> CGFloat {
        let level = CGFloat(audioLevel)
        return min(level * Self.multipliers[index], 1.0)
    }
}

// MARK: - Dots

struct DotsView: View {
    @State private var activeDot = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(activeDot == index ? 0.9 : 0.25))
                    .frame(width: 4.5, height: 4.5)
                    .animation(.easeInOut(duration: 0.4), value: activeDot)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { break }
                activeDot = (activeDot + 1) % 3
            }
        }
    }
}

// MARK: - Error content

struct OverlayErrorContent: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

// MARK: - Pill overlay

struct RecordingOverlayView: View {
    var state: RecordingOverlayState

    var body: some View {
        HStack(spacing: 10) {
            Group {
                switch state.phase {
                case .errorNoMic:
                    OverlayErrorContent(icon: "mic.slash.fill", color: .red, text: "Access Not Granted")
                        .transition(.opacity)
                case .errorNoAccessibility:
                    OverlayErrorContent(icon: "hand.raised.fill", color: .red, text: "Accessibility Off")
                        .transition(.opacity)
                case .errorNoModel:
                    OverlayErrorContent(icon: "exclamationmark.triangle.fill", color: .orange, text: "No Model")
                        .transition(.opacity)
                case .errorNoSpeech:
                    OverlayErrorContent(icon: "waveform.slash", color: .secondary, text: "No Speech Detected")
                        .transition(.opacity)
                case .errorGeneric(let message):
                    OverlayErrorContent(icon: "exclamationmark.triangle.fill", color: .orange, text: message)
                        .transition(.opacity)
                case .initializing, .transcribing:
                    DotsView()
                        .transition(.opacity)
                case .recording, .done:
                    WaveformView(audioLevel: state.audioLevel)
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(Color.black)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: state.phase)
    }
}
