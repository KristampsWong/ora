//
//  ModelManager.swift
//  ora
//
//  Mock model catalog for ModelsPage. No backend wiring.
//

import Foundation

enum ModelManager {
    static let mockModels: [ModelEntry] = [
        ModelEntry(
            id: "parakeet-v3",
            name: "Nvidia Parakeet Tdt 0.6B V3",
            description: "Ultra-fast transcription powered by NVIDIA FastConformer. Optimized for conversational speech and voice commands.",
            badge: nil,
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
            badge: nil,
            accuracy: 5,
            speed: 5,
            size: "490 MB",
            language: "English",
            isLocal: true,
            isOnline: false,
            status: .notDownloaded
        ),
        ModelEntry(
            id: "openai-api",
            name: "OpenAI API",
            description: "OpenAI API for transcription. GPT-4o Transcribe is recommended.",
            badge: "Recommended",
            accuracy: 5,
            speed: 4,
            size: "$0.006/min",
            language: "Multilingual",
            isLocal: false,
            isOnline: true,
            status: .downloaded
        ),
        ModelEntry(
            id: "groq-api",
            name: "Groq API",
            description: "Groq API for transcription. Whisper Large v3 is recommended.",
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
