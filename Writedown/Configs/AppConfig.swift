//
//  AppConfig.swift
//  Writedown
//
//  Created by LC John on 1/16/25.
//

import Foundation

/// Application configuration settings
enum AppConfig {
    enum QuickWakeup {
        static let dailyLimit = 100
    }

    // 未来可以在这里添加其他配置类别
    // enum OtherFeature { ... }
}

struct AIModel: Identifiable, Equatable {
    var id: String { modelId }
    let modelId: String
    let displayName: String
    /// If true, the model is only available for Pro users.
    let isProOnly: Bool
}

struct AIModelConfig {
    /// Maintain the mapping of model IDs to a friendly name and availability.
    static let availableModels: [AIModel] = [
        AIModel(
            modelId: "ep-20250212220411-mtfqd", displayName: "Doubao-lite-32k",
            isProOnly: false),
        // Pro-only model – only selectable when the user is Pro.
        AIModel(
            modelId: "ep-20250128221733-ldppp", displayName: "Doubao-1.5-pro-32k",
            isProOnly: false),
        // Standard model – available for all users.
        AIModel(
            modelId: "ep-20250208231403-7dmtb", displayName: "DeepSeek-V3", isProOnly: true),
//        AIModel(
//            modelId: "ep-20250213001714-xxx2w", displayName: "DeepSeek-R1-7B", isProOnly: true),
    ]
}

enum AppearanceMode: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
}
