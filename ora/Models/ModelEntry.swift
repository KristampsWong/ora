//
//  ModelEntry.swift
//  ora
//
//  Data type for a transcription model entry — shared by the catalog
//  (Models/ModelManager) and the UI (UI/Settings/ModelsPage).
//

import Foundation

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

    /// Asset name for the provider's brand icon (OpenAI / NVIDIA / Groq).
    /// `nil` falls back to the card's generic SF Symbol.
    var brandIconAsset: String? {
        switch id {
        case "parakeet-v2", "parakeet-v3": "BrandNvidia"
        case "openai-api": "BrandOpenAI"
        case "groq-api": "BrandGroq"
        default: nil
        }
    }

    enum Status: Equatable {
        case downloaded
        case notDownloaded
        /// `eta` is `nil` until the downloader has accumulated enough samples
        /// to estimate a remaining time (typically the first ~4 seconds, or
        /// any time speed drops to 0).
        case downloading(eta: TimeInterval?)
        case paused
        case extracting
        case error(message: String)
    }
}
