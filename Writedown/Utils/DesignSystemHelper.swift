//
//  DesignSystemHelper.swift
//  Writedown
//
//  Created for macOS 26 Liquid Glass adaptation
//  Provides version detection and design system utilities
//

import AppKit
import SwiftUI

// MARK: - Design System Version Detection

/// Helper struct for detecting and adapting to different macOS design systems
struct DesignSystem {
    
    /// Returns true if the current system supports Liquid Glass (macOS 26+)
    static var supportsLiquidGlass: Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }
    
    /// Returns true if running on macOS 15 (Sequoia) or later
    static var isSequoiaOrLater: Bool {
        if #available(macOS 15.0, *) {
            return true
        }
        return false
    }
    
    /// The recommended corner radius for the current design system
    static var standardCornerRadius: CGFloat {
        if #available(macOS 26.0, *) {
            return 16 // Larger, softer corners for Liquid Glass
        }
        return 12 // Traditional macOS corner radius
    }
    
    /// The recommended small corner radius for buttons and controls
    static var smallCornerRadius: CGFloat {
        if #available(macOS 26.0, *) {
            return 10
        }
        return 8
    }
}

// MARK: - Adaptive Glass Background Modifier

/// A view modifier that applies appropriate background based on macOS version
struct AdaptiveGlassBackground: ViewModifier {
    var material: NSVisualEffectView.Material
    var cornerRadius: CGFloat?
    
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            // macOS 26+: Use new glass effect system
            // Note: The actual .glassEffect() API will be available in Xcode 26
            // For now, we use a placeholder that can be updated
            content
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius ?? DesignSystem.standardCornerRadius)
                        .fill(.ultraThinMaterial)
                }
        } else {
            // macOS 15-25: Use traditional NSVisualEffectView
            content
                .background(
                    LegacyVisualEffectView(material: material)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? DesignSystem.standardCornerRadius))
                )
        }
    }
}

// MARK: - View Extension

extension View {
    /// Applies an adaptive glass background that uses Liquid Glass on macOS 26+
    /// and falls back to NSVisualEffectView on older systems
    func adaptiveGlassBackground(
        material: NSVisualEffectView.Material = .sidebar,
        cornerRadius: CGFloat? = nil
    ) -> some View {
        modifier(AdaptiveGlassBackground(material: material, cornerRadius: cornerRadius))
    }
    
    /// Applies background only on macOS 26+ (Liquid Glass era)
    @ViewBuilder
    func liquidGlassOnly<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        if #available(macOS 26.0, *) {
            self.background(content())
        } else {
            self
        }
    }
    
    /// Applies background only on pre-macOS 26 systems
    @ViewBuilder
    func legacyOnly<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        if #available(macOS 26.0, *) {
            self
        } else {
            self.background(content())
        }
    }
}

// MARK: - Legacy Visual Effect View (for backward compatibility)

/// NSViewRepresentable wrapper for NSVisualEffectView (used on macOS 15-25)
struct LegacyVisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    var state: NSVisualEffectView.State = .active
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.wantsLayer = true
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

// MARK: - Adaptive Material Background

/// SwiftUI Material that adapts to macOS version
struct AdaptiveMaterial: View {
    var style: MaterialStyle
    
    enum MaterialStyle {
        case thin
        case regular
        case thick
        case sidebar
        case hudWindow
        
        var legacyMaterial: NSVisualEffectView.Material {
            switch self {
            case .thin: return .headerView
            case .regular: return .contentBackground
            case .thick: return .sidebar
            case .sidebar: return .sidebar
            case .hudWindow: return .hudWindow
            }
        }
        
        @available(macOS 15.0, *)
        var swiftUIMaterial: Material {
            switch self {
            case .thin: return .thinMaterial
            case .regular: return .regularMaterial
            case .thick: return .thickMaterial
            case .sidebar: return .regularMaterial
            case .hudWindow: return .ultraThinMaterial
            }
        }
    }
    
    var body: some View {
        if #available(macOS 26.0, *) {
            // macOS 26+: Will use Liquid Glass when API is available
            Rectangle().fill(.ultraThinMaterial)
        } else {
            LegacyVisualEffectView(material: style.legacyMaterial)
        }
    }
}

// MARK: - Window Configuration Helpers

/// Helper class for configuring windows based on macOS version
class WindowConfigurationHelper {
    
    /// Configures a window for the appropriate design system
    static func configureForDesignSystem(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        
        if #available(macOS 26.0, *) {
            // macOS 26+: Let system handle Liquid Glass
            // Don't set backgroundColor to clear - let the glass material show through
            window.isOpaque = false
        } else {
            // macOS 15-25: Traditional transparent window setup
            window.backgroundColor = .clear
            window.isOpaque = false
        }
        
        // Common settings
        window.styleMask.insert(.fullSizeContentView)
    }
    
    /// Configures a floating panel window
    static func configureAsFloatingPanel(_ window: NSWindow) {
        configureForDesignSystem(window)
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
    
    /// Sets up a window with visual effect background
    static func addVisualEffectBackground(to window: NSWindow, material: NSVisualEffectView.Material = .sidebar) {
        if #available(macOS 26.0, *) {
            // macOS 26+: System handles glass automatically for standard window elements
            // Only add manual glass for custom floating elements
        } else {
            // macOS 15-25: Add NSVisualEffectView manually
            let visualEffectView = NSVisualEffectView()
            visualEffectView.material = material
            visualEffectView.blendingMode = .behindWindow
            visualEffectView.state = .active
            visualEffectView.autoresizingMask = [.width, .height]
            visualEffectView.frame = window.contentView?.bounds ?? .zero
            
            if let contentView = window.contentView {
                contentView.addSubview(visualEffectView, positioned: .below, relativeTo: nil)
            }
        }
    }
}

// MARK: - Color Adaptations

extension Color {
    /// Returns an adaptive separator color for the current design system
    static var adaptiveSeparator: Color {
        if #available(macOS 26.0, *) {
            return Color.primary.opacity(0.1)
        }
        return Color.gray.opacity(0.2)
    }
    
    /// Returns an adaptive secondary background color
    static var adaptiveSecondaryBackground: Color {
        if #available(macOS 26.0, *) {
            return Color.primary.opacity(0.05)
        }
        return Color.gray.opacity(0.1)
    }
}

// MARK: - Preview

#if DEBUG
struct DesignSystemHelper_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            Text("Design System Helper")
                .font(.headline)
            
            Text("Supports Liquid Glass: \(DesignSystem.supportsLiquidGlass ? "Yes" : "No")")
            Text("Standard Corner Radius: \(Int(DesignSystem.standardCornerRadius))")
            
            Text("Sample Glass Background")
                .padding()
                .adaptiveGlassBackground()
        }
        .padding()
        .frame(width: 300, height: 200)
    }
}
#endif

// MARK: - Localization Manager

struct Language: Identifiable, Hashable {
    let code: String
    let name: String
    var id: String { code }
}

class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    @Published var currentLanguage: Language = .en {
        didSet {
            UserDefaults.standard.set(currentLanguage.code, forKey: "selectedLanguage")
            NotificationCenter.default.post(name: .languageDidChange, object: nil)
        }
    }

    static let supportedLanguages: [Language] = [
        .en,
        .zh,
    ]
    
    private let translations: [String: [String: String]] = [
        "No notes": ["zh-Hans": "暂无笔记"],
        "No matching notes": ["zh-Hans": "未找到匹配的笔记"],
        "Summarizing...": ["zh-Hans": "正在生成摘要..."],
        "Copy": ["zh-Hans": "复制"],
        "Share": ["zh-Hans": "分享"],
        "Remove Star": ["zh-Hans": "取消收藏"],
        "Add Star": ["zh-Hans": "添加收藏"],
        "Archive Note": ["zh-Hans": "归档笔记"],
        "Language": ["zh-Hans": "语言"],
        "English": ["zh-Hans": "英语"],
        "Font": ["zh-Hans": "字体"],
        "Appearance": ["zh-Hans": "外观"],
        "Check for updates": ["zh-Hans": "检查更新"],
        "Latest available": ["zh-Hans": "已是最新版本"],
        "Version": ["zh-Hans": "版本"],
        "Build": ["zh-Hans": "构建版本"],
        "Double press Option key": ["zh-Hans": "双击 Option 键"],
        "Cmd + C (double click)": ["zh-Hans": "Cmd + C (双击)"],
        "Unlimited quick wake-ups (Pro)": ["zh-Hans": "无限快速唤醒 (Pro)"],
        "© 2025 ProductLab. All rights reserved.": ["zh-Hans": "© 2025 ProductLab. 保留所有权利。"],
        "Open Writedown": ["zh-Hans": "打开 Writedown"],
        "Content Saved": ["zh-Hans": "内容已保存"],
        "Settings": ["zh-Hans": "设置"],
        "General": ["zh-Hans": "通用"],
        "About": ["zh-Hans": "关于"],
        "Quit": ["zh-Hans": "退出"],
        "Preferences": ["zh-Hans": "偏好设置"],
        "Shortcut": ["zh-Hans": "快捷键"],
        "Display": ["zh-Hans": "显示"],
        "Update": ["zh-Hans": "更新"],
        "Cancel": ["zh-Hans": "取消"],
        "Done": ["zh-Hans": "完成"]
    ]

    private init() {
        let savedLangCode = UserDefaults.standard.string(forKey: "selectedLanguage") ?? "en"
        currentLanguage = Language.from(code: savedLangCode) ?? .en
    }

    func localizedString(_ key: String) -> String {
        if currentLanguage.code == "en" { return key }
        return translations[key]?[currentLanguage.code] ?? key
    }
}

extension Language {
    static let en = Language(code: "en", name: "English")
    static let zh = Language(code: "zh-Hans", name: "简体中文")

    static func from(code: String) -> Language? {
        LocalizationManager.supportedLanguages.first { $0.code == code }
    }
}

extension Notification.Name {
    static let languageDidChange = Notification.Name("languageDidChange")
}

func L(_ key: String) -> String {
    return LocalizationManager.shared.localizedString(key)
}

