//
//  APITranscriber.swift
//  ora
//
//  Cloud `Transcriber` for OpenAI-compatible /audio/transcriptions
//  endpoints. Both OpenAI and Groq speak the same multipart shape
//  (model + file fields, Bearer auth), so one implementation covers
//  both — only the base URL and the stored key/model differ.
//
//  ## Pipeline
//
//   1. Pull the PCM buffer from Recorder (16 kHz mono Float32).
//   2. Encode to an AAC/m4a temp file via AVAudioFile — ~10x smaller
//      than WAV, fine for hold-to-talk where recordings are seconds.
//   3. POST multipart/form-data with Bearer auth.
//   4. Decode `{ "text": "..." }` from the JSON response.
//
//  ## Credentials
//
//  API keys live in the Keychain (`KeychainStore`), keyed by provider
//  id. The chosen model name (e.g. "gpt-4o-transcribe",
//  "whisper-large-v3") lives in UserDefaults at `api.<id>.model` since
//  it's not a secret. Both are populated by `APIModelCard`'s settings
//  sheet.
//

import AVFoundation
import Foundation

final class APITranscriber: Transcriber {
    enum Failure: Error, LocalizedError {
        case missingAPIKey
        case missingModel
        case emptyAudio
        case encodingFailed(Error)
        case network(Error)
        case httpStatus(Int, String)
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Add your API key in Settings ▸ Models."
            case .missingModel:
                return "Set a model name in Settings ▸ Models."
            case .emptyAudio:
                return "The recording was empty."
            case .encodingFailed(let error):
                return "Couldn't encode audio: \(error.localizedDescription)"
            case .network(let error):
                return "Network error: \(error.localizedDescription)"
            case .httpStatus(let code, let body):
                let snippet = body.prefix(160)
                return "API returned \(code): \(snippet)"
            case .decodingFailed:
                return "Couldn't parse the API response."
            }
        }
    }

    struct Provider: Equatable {
        let id: String
        let endpoint: URL
    }

    /// Returns the supported provider for a catalog id, or `nil` if
    /// we don't know how to talk to that one. New providers (Deepgram,
    /// ElevenLabs, etc.) plug in here.
    static func provider(for id: String) -> Provider? {
        switch id {
        case "openai-api":
            return Provider(
                id: id,
                endpoint: URL(string: "https://api.openai.com/v1/audio/transcriptions")!
            )
        case "groq-api":
            return Provider(
                id: id,
                endpoint: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
            )
        default:
            return nil
        }
    }

    /// UserDefaults key for the model name (non-secret) paired with a provider.
    static func modelDefaultsKey(for providerId: String) -> String {
        "api.\(providerId).model"
    }

    private let provider: Provider
    private let urlSession: URLSession

    init(provider: Provider, urlSession: URLSession = .shared) {
        self.provider = provider
        self.urlSession = urlSession
    }

    // MARK: - Transcriber

    func transcribe(_ buffer: AVAudioPCMBuffer) async throws -> String {
        guard buffer.frameLength > 0 else { throw Failure.emptyAudio }

        guard let apiKey = KeychainStore.apiKey(provider: provider.id) else {
            throw Failure.missingAPIKey
        }
        let modelName = UserDefaults.standard.string(forKey: Self.modelDefaultsKey(for: provider.id)) ?? ""
        guard !modelName.isEmpty else { throw Failure.missingModel }

        let fileURL: URL
        do {
            fileURL = try Self.writeAAC(buffer: buffer)
        } catch {
            throw Failure.encodingFailed(error)
        }
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let audioData: Data
        do {
            audioData = try Data(contentsOf: fileURL)
        } catch {
            throw Failure.encodingFailed(error)
        }

        let boundary = "ora-\(UUID().uuidString)"
        var request = URLRequest(url: provider.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(boundary: boundary, model: modelName, audio: audioData)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw Failure.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw Failure.decodingFailed
        }
        if !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw Failure.httpStatus(http.statusCode, body)
        }

        struct Body: Decodable { let text: String }
        guard let decoded = try? JSONDecoder().decode(Body.self, from: data) else {
            throw Failure.decodingFailed
        }
        return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Encoding

    /// Writes a Float32 mono 16 kHz PCM buffer into a temporary AAC
    /// (.m4a) file and returns its URL. AVAudioFile handles the PCM→AAC
    /// conversion internally via ExtAudioFile; the processing format it
    /// exposes matches the input buffer so `write(from:)` is a direct
    /// feed. Caller owns the file and is responsible for deletion.
    private static func writeAAC(buffer: AVAudioPCMBuffer) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ora-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: buffer.format.sampleRate,
            AVNumberOfChannelsKey: Int(buffer.format.channelCount),
            AVEncoderBitRateKey: 32000,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer)
        return url
    }

    // MARK: - Multipart

    private static func multipartBody(boundary: String, model: String, audio: Data) -> Data {
        var body = Data()
        func append(_ s: String) {
            if let d = s.data(using: .utf8) { body.append(d) }
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("\(model)\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        append("json\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n")
        append("Content-Type: audio/mp4\r\n\r\n")
        body.append(audio)
        append("\r\n")

        append("--\(boundary)--\r\n")
        return body
    }
}
