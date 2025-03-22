//
//  AppStorageManager.swift
//  Writedown
//
//  Created by LC John on 3/22/25.
//

import Foundation
import SwiftUI

/// Enum containing all AppStorage keys used throughout the app
enum AppStorageKeys {
    // General Settings
    static let launchAtLogin = "launchAtLogin"
    static let userName = "userName"
    static let userEmail = "userEmail"
    static let userAvatar = "userAvatar"
    static let hasRequestedLaunchPermission = "hasRequestedLaunchPermission"
    static let isPro = "isPro"

    // Note Settings
    static let AIModel = "AIModel"
    static let enableAIRename = "enableAIRename"
    static let editorFont = "editorFont"
    static let autoSaveInterval = "autoSaveInterval"
    static let notionIntegration = "notionIntegration"

    // Appearance Settings
    static let appearanceMode = "appearanceMode"

    // Hotkey Settings
    static let enableDoubleOption = "enableDoubleOption"
}

/// Structure containing all default values for AppStorage properties
struct AppDefaults {
    // General Settings
    static let launchAtLogin = false
    static let userName = ""
    static let userEmail = ""
    static let userAvatar = ""
    static let hasRequestedLaunchPermission = false
    static let isPro = false

    // Note Settings
    static let AIModel = AIModelConfig.availableModels.first { !$0.isProOnly }?.modelId ?? "Doubao-lite-32k"
    static let enableAIRename = true
    static let editorFont = "System"
    static let autoSaveInterval: TimeInterval = 10
    static let notionIntegration = false

    // Appearance Settings
    static let appearanceMode = AppearanceMode.system

    // Hotkey Settings
    static let enableDoubleOption = true
}

// Usage example (for demonstration):
// @AppStorage(AppStorageKeys.isPro) private var isPro: Bool = AppDefaults.isPro
