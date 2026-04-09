//
//  Transcriber.swift
//  ora
//
//  Protocol for "given a recorded audio buffer, return text". The
//  contract is intentionally tiny — one method, no streaming, no
//  partial results — because hold-to-talk dictation only ever needs
//  a final transcript at the moment the user releases the hotkey.
//
//  ## Why a protocol at all
//
//  v1 ships exactly one implementation (`FluidAudioTranscriber`),
//  which is normally a sign that an abstraction is premature. The
//  exception here is that WhisperKit is a known, concrete future
//  addition for non-European languages (see M7 in the roadmap), and
//  it slots in as a second `Transcriber` with no caller changes.
//  The protocol earns its keep by being ~10 lines today and saving
//  a refactor when WhisperKit lands.
//
//  ## Threading
//
//  The whole target runs `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
//  which makes this protocol implicitly main-actor isolated. That's
//  the right level for the dictation pipeline: `Recorder.stop()`
//  returns on the main actor, the coordinator state machine lives on
//  the main actor, and the paste step is main-actor as well.
//  Implementations are free to hop to a background actor internally
//  (and `FluidAudioTranscriber` does, since `AsrManager` is its own
//  actor) — they just need to come back to main before returning.
//

import AVFoundation

protocol Transcriber {
    /// Transcribes a single 16 kHz mono Float32 PCM buffer into text.
    /// The buffer is consumed in one shot — there is no chunking or
    /// streaming contract. Implementations may load the underlying
    /// model lazily on the first call.
    ///
    /// Throws an implementation-specific error if the model isn't
    /// available, the audio is empty, or inference fails. Callers
    /// should treat any thrown error as fatal for the current
    /// utterance and surface a message to the user.
    func transcribe(_ buffer: AVAudioPCMBuffer) async throws -> String
}
