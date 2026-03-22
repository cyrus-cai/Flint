//
//  AppStorageManager.swift
//  Flint
//
//  Created by LC John on 3/22/25.
//

import Foundation
import SwiftUI

/// Enum containing all AppStorage keys used throughout the app
enum AppStorageKeys {
    // General Settings
    static let launchAtLogin = "launchAtLogin"
    static let hasRequestedLaunchPermission = "hasRequestedLaunchPermission"

    // AI Settings
    static let AIProvider = "AIProvider"
    static let AIModel = "AIModel" // Legacy, migrated to per-provider keys
    static let miniMaxAPIKey = "MiniMaxAPIKey" // Legacy, migrated to Keychain
    static let enableAIRename = "enableAIRename"
    static let enableAutoSaveClipboard = "enableAutoSaveClipboard"
    static let editorFont = "editorFont"
    static let autoSaveInterval = "autoSaveInterval"
    static let notionIntegration = "notionIntegration"
    static let showWordCount = "showWordCount"

    // Appearance Settings
    static let appearanceMode = "appearanceMode"

    // Hotkey Settings
    static let enableDoubleOption = "enableDoubleOption"
}

/// Structure containing all default values for AppStorage properties
struct AppDefaults {
    // General Settings
    static let launchAtLogin = false
    static let hasRequestedLaunchPermission = false

    // AI Settings
    static let AIProviderDefault = AIProvider.minimax.rawValue
    static let AIModel = AIModelConfig.availableModels.first?.modelId ?? "MiniMax-M2.5"
    static let miniMaxAPIKey = ""
    static let enableAIRename = false
    static let enableAutoSaveClipboard = false
    static let editorFont = "System"
    static let autoSaveInterval: TimeInterval = 10
    static let notionIntegration = false
    static let showWordCount = false

    // Appearance Settings
    static let appearanceMode = AppearanceMode.system

    // Hotkey Settings
    static let enableDoubleOption = true
}
