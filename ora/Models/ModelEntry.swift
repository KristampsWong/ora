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

    enum Status: Equatable {
        case downloaded
        case notDownloaded
        case downloading(progress: Double)
        case paused(progress: Double)
        case extracting
        case error(message: String)
    }
}
