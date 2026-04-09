//
//  MenuBarView.swift
//  ora
//
//  Menu bar dropdown — native NSMenu style.
//  Hosted by a MenuBarExtra(.menu) so each Button/Menu/Divider here
//  becomes a real NSMenuItem rather than a custom popover row.
//

import AVFoundation
import SwiftUI

struct MenuBarView: View {
    @State private var isRecording = false
    @State private var selectedInputName = "MacBook Pro Microphone"
    #if DEBUG
    @State private var devRecorder = Recorder()
    @State private var devRecordingBusy = false
    @State private var devPaster = Paster()
    @State private var devPasteBusy = false
    @State private var devTranscriber = FluidAudioTranscriber()
    @State private var devTranscribeBusy = false
    #endif

    private static let mockInputDevices = [
        "MacBook Pro Microphone",
        "AirPods Pro",
        "External USB Mic",
    ]

    var body: some View {
        // Recording toggle
        Button(isRecording ? "Stop Recording" : "Start Recording") {
            isRecording.toggle()
        }
        .keyboardShortcut(.space, modifiers: .option)

        Divider()

        // Settings pages — sourced from SettingsPage.allCases so the
        // sidebar and menu stay in sync automatically.
        ForEach(SettingsPage.allCases) { page in
            Button {
                // TODO: open Settings on the matching page when navigation is wired.
            } label: {
                Label(page.title, systemImage: page.icon)
            }
        }

        Divider()

        // Input source submenu
        Menu("Input Source") {
            ForEach(Self.mockInputDevices, id: \.self) { device in
                Button {
                    selectedInputName = device
                } label: {
                    if device == selectedInputName {
                        Label(device, systemImage: "checkmark")
                    } else {
                        Text(device)
                    }
                }
            }
        }

        Divider()

        #if DEBUG
        // M2 dev harness — records 3 seconds from the default mic,
        // writes the buffer to a temp dir as WAV, and prints the
        // resolved path so you can `open` it in Finder / QuickTime.
        // Scheduled for removal when M6 lands (see roadmap).
        Button(devRecordingBusy ? "Recording… (3s)" : "Test Record 3s") {
            Task { await runDevRecordTest() }
        }
        .disabled(devRecordingBusy)

        // M5 dev harness — pastes a hardcoded string into whatever app
        // was frontmost before the menu opened. Verifies the clipboard
        // hijack + synthetic Cmd+V + restore loop in isolation, before
        // the dictation coordinator wires real transcripts in M6.
        // Scheduled for removal alongside the other dev items in M6.
        Button(devPasteBusy ? "Pasting…" : "Test Paste") {
            Task { await runDevPasteTest() }
        }
        .disabled(devPasteBusy)

        // M3 dev harness — records 5 seconds, runs the buffer through
        // FluidAudioTranscriber, prints the result. The first run pays
        // a one-time ~1–2 s model load cost; subsequent runs are
        // ~realtime÷100 on M-series. Removed alongside the others in M6.
        Button(devTranscribeBusy ? "Transcribing…" : "Test Transcribe 5s") {
            Task { await runDevTranscribeTest() }
        }
        .disabled(devTranscribeBusy)

        Divider()
        #endif

        Text(versionString)

        Button("Check for Updates") {
            // TODO: wire to update checker.
        }

        Divider()

        Button("Quit Ora") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        return "Version \(version)"
    }

    #if DEBUG
    /// Records 3 seconds of audio and writes it as a WAV file inside
    /// the sandbox temporary directory. The resolved path is printed
    /// to stdout so you can locate the file in Finder (the sandbox
    /// rewrites `/tmp/...` to a container-local path, so we log the
    /// real URL rather than the conceptual one).
    @MainActor
    private func runDevRecordTest() async {
        devRecordingBusy = true
        defer { devRecordingBusy = false }

        // Kick the consent dialog if this is the first run. If the
        // user has previously denied, `request()` returns false
        // without prompting — bail out with a clear log line.
        let granted = await MicrophonePermission.request()
        guard granted else {
            print("[DevRecord] Microphone access not granted — open System Settings ▸ Privacy & Security ▸ Microphone to allow Ora.")
            return
        }

        do {
            try devRecorder.start()
            try await Task.sleep(for: .seconds(3))
            let buffer = try devRecorder.stop()

            let url = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("ora-test.wav")
            // Remove any previous run's file so AVAudioFile doesn't
            // refuse to overwrite.
            try? FileManager.default.removeItem(at: url)
            try Recorder.writeWav(buffer: buffer, to: url)

            print("[DevRecord] Wrote \(buffer.frameLength) frames @ \(buffer.format.sampleRate) Hz to \(url.path)")
            print("[DevRecord] open \"\(url.path)\"")
        } catch {
            print("[DevRecord] Failed: \(error.localizedDescription)")
        }
    }

    /// Pastes a hardcoded "hello world" into whatever app was frontmost
    /// before the menu opened. Verifies the M5 paste path end-to-end:
    /// snapshot pasteboard, set transcript, synthesize Cmd+V, restore.
    /// Will be removed when the dictation coordinator lands in M6.
    @MainActor
    private func runDevPasteTest() async {
        devPasteBusy = true
        defer { devPasteBusy = false }

        // The MenuBarExtra(.menu) host doesn't activate Ora when the
        // menu is opened, so the previously-frontmost app stays frontmost
        // and is the right paste target. We still wait a beat for the
        // menu to fully dismiss before posting Cmd+V — without this, on
        // a slow first-run the synthetic event can race the menu close
        // animation and get swallowed.
        try? await Task.sleep(for: .milliseconds(80))

        if !Paster.isTrusted {
            // Surface the system prompt that adds Ora to the
            // Accessibility list. The first call shows the prompt; the
            // user has to enable us in System Settings, restart Ora,
            // then try again. Subsequent calls are silent.
            Paster.requestTrust(prompt: true)
            print("[DevPaste] Accessibility access not granted — approve Ora in System Settings ▸ Privacy & Security ▸ Accessibility, then relaunch and try again.")
            return
        }

        do {
            try await devPaster.paste("hello world")
            print("[DevPaste] Pasted 'hello world' to frontmost app.")
        } catch {
            print("[DevPaste] Failed: \(error.localizedDescription)")
        }
    }

    /// Records 5 seconds of microphone audio, hands the buffer to the
    /// FluidAudio transcriber, and prints the result. Verifies the M3
    /// path end-to-end (record → resample → load model → infer) before
    /// the dictation coordinator wires it together for real in M6.
    @MainActor
    private func runDevTranscribeTest() async {
        devTranscribeBusy = true
        defer { devTranscribeBusy = false }

        let granted = await MicrophonePermission.request()
        guard granted else {
            print("[DevTranscribe] Microphone access not granted — open System Settings ▸ Privacy & Security ▸ Microphone to allow Ora.")
            return
        }

        do {
            try devRecorder.start()
            try await Task.sleep(for: .seconds(5))
            let buffer = try devRecorder.stop()
            print("[DevTranscribe] Captured \(buffer.frameLength) frames @ \(buffer.format.sampleRate) Hz, transcribing…")

            // First call may take ~1–2 s extra to load the four CoreML
            // models from the cache; subsequent calls reuse the loaded
            // AsrManager and return at ~100× realtime on M-series.
            let started = Date()
            let text = try await devTranscriber.transcribe(buffer)
            let elapsed = Date().timeIntervalSince(started)
            print(String(format: "[DevTranscribe] %.2fs → %@", elapsed, text.isEmpty ? "(empty)" : text))
        } catch {
            print("[DevTranscribe] Failed: \(error.localizedDescription)")
        }
    }
    #endif
}
