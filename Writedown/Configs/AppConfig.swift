//
//  AppConfig.swift
//  Writedown
//
//  Created by LC John on 1/16/25.
//

import Foundation

struct AIModel: Identifiable, Equatable {
    var id: String { modelId }
    let modelId: String
    let displayName: String
}

struct AIModelConfig {
    /// Maintain the mapping of model IDs to a friendly name and availability.
    static let availableModels: [AIModel] = [
        AIModel(modelId: "MiniMax-M2.5", displayName: "MiniMax M2.5"),
        AIModel(modelId: "MiniMax-M2.5-highspeed", displayName: "MiniMax M2.5 Highspeed"),
        AIModel(modelId: "MiniMax-M2.1", displayName: "MiniMax M2.1"),
        AIModel(modelId: "MiniMax-M2.1-highspeed", displayName: "MiniMax M2.1 Highspeed"),
    ]
}

enum AppearanceMode: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
}
