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
        // ✅ Working endpoint - set as default
        AIModel(
            modelId: "ep-20250128221733-ldppp", displayName: "Doubao-1.5-pro-32k"),
        // ❌ Deprecated endpoints (closed/unavailable)
        // AIModel(
        //     modelId: "ep-20250212220411-mtfqd", displayName: "Doubao-lite-32k [CLOSED]"),
        // AIModel(modelId: "ep-20250208231403-7dmtb", displayName: "DeepSeek-V3 [CLOSED]"),
        // AIModel(modelId: "ep-20250213001714-xxx2w", displayName: "DeepSeek-R1-7B"),
    ]
}

enum AppearanceMode: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
}
