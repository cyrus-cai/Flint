//
//  AppConfig.swift
//  Flint
//
//  Created by LC John on 1/16/25.
//

import Foundation

struct AIModel: Identifiable, Equatable {
    var id: String { modelId }
    let modelId: String
    let displayName: String
}

// MARK: - AI Provider

enum AIProvider: String, CaseIterable, Identifiable {
    case minimax
    case kimi

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .minimax: return "MiniMax"
        case .kimi: return "Kimi"
        }
    }

    var chatCompletionsURL: String {
        switch self {
        case .minimax: return "https://api.minimax.io/v1/chat/completions"
        case .kimi: return "https://api.moonshot.cn/v1/chat/completions"
        }
    }

    var keychainKey: String {
        switch self {
        case .minimax: return "com.flint.minimax-api-key"
        case .kimi: return "com.flint.kimi-api-key"
        }
    }

    var websiteURL: String {
        switch self {
        case .minimax: return "https://platform.minimax.io/user-center/basic-information/interface-key"
        case .kimi: return "https://platform.moonshot.cn/console/api-keys"
        }
    }

    var modelStorageKey: String {
        switch self {
        case .minimax: return "AIModel_minimax"
        case .kimi: return "AIModel_kimi"
        }
    }

    var enableAIRenameKey: String {
        "enableAIRename_\(rawValue)"
    }

    var enableAutoSaveClipboardKey: String {
        "enableAutoSaveClipboard_\(rawValue)"
    }

    var models: [AIModel] {
        switch self {
        case .minimax:
            return [
                AIModel(modelId: "MiniMax-M2.5", displayName: "MiniMax M2.5"),
                AIModel(modelId: "MiniMax-M2.5-highspeed", displayName: "MiniMax M2.5 Highspeed"),
                AIModel(modelId: "MiniMax-M2.1", displayName: "MiniMax M2.1"),
                AIModel(modelId: "MiniMax-M2.1-highspeed", displayName: "MiniMax M2.1 Highspeed"),
            ]
        case .kimi:
            return [
                AIModel(modelId: "kimi-k2.5", displayName: "Kimi K2.5"),
                AIModel(modelId: "kimi-k2-0905-preview", displayName: "Kimi K2"),
                AIModel(modelId: "kimi-k2-turbo-preview", displayName: "Kimi K2 Turbo"),
            ]
        }
    }

    var defaultModelId: String {
        switch self {
        case .minimax: return "MiniMax-M2.5"
        case .kimi: return "kimi-k2.5"
        }
    }
}

struct AIModelConfig {
    static var availableModels: [AIModel] {
        let raw = UserDefaults.standard.string(forKey: AppStorageKeys.AIProvider) ?? AIProvider.minimax.rawValue
        let provider = AIProvider(rawValue: raw) ?? .minimax
        return provider.models
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let aiProviderDidChange = Notification.Name("aiProviderDidChange")
    static let windowTransparencyDidChange = Notification.Name("windowTransparencyDidChange")
}

enum AppearanceMode: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
}
