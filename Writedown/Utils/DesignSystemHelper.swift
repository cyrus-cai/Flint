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
        .zhHant,
    ]
    
    private let translations: [String: [String: String]] = [
        "No notes": ["zh-Hans": "暂无笔记", "zh-Hant": "暫無筆記"],
        "No matching notes": ["zh-Hans": "未找到匹配的笔记", "zh-Hant": "未找到匹配的筆記"],
        "Summarizing...": ["zh-Hans": "正在生成摘要...", "zh-Hant": "正在生成摘要..."],
        "Copy": ["zh-Hans": "复制", "zh-Hant": "複製"],
        "Share": ["zh-Hans": "分享", "zh-Hant": "分享"],
        "Remove Star": ["zh-Hans": "取消收藏", "zh-Hant": "取消收藏"],
        "Add Star": ["zh-Hans": "添加收藏", "zh-Hant": "新增收藏"],
        "Archive Note": ["zh-Hans": "归档笔记", "zh-Hant": "封存筆記"],
        "Language": ["zh-Hans": "语言", "zh-Hant": "語言"],
        "English": ["zh-Hans": "英语", "zh-Hant": "英語"],
        "Font": ["zh-Hans": "字体", "zh-Hant": "字型"],
        "Appearance": ["zh-Hans": "外观", "zh-Hant": "外觀"],
        "Check for updates": ["zh-Hans": "检查更新", "zh-Hant": "檢查更新"],
        "Latest available": ["zh-Hans": "已是最新版本", "zh-Hant": "已是最新版本"],
        "Double press Option key": ["zh-Hans": "双击 Option 键", "zh-Hant": "雙擊 Option 鍵"],
        "Cmd + C (double click)": ["zh-Hans": "Cmd + C (双击)", "zh-Hant": "Cmd + C (雙擊)"],
        "Stop": ["zh-Hans": "停止", "zh-Hant": "停止"],
        "No more notes": ["zh-Hans": "没有更多笔记了", "zh-Hant": "沒有更多筆記了"],
        "Welcome to Writedown": ["zh-Hans": "欢迎使用 Writedown", "zh-Hant": "歡迎使用 Writedown"],
        "© 2025 ProductLab. All rights reserved.": ["zh-Hans": "© 2025 ProductLab. 保留所有权利。", "zh-Hant": "© 2025 ProductLab. 保留所有權利。"],
        "Open Writedown": ["zh-Hans": "打开 Writedown", "zh-Hant": "開啟 Writedown"],
        "Content Saved": ["zh-Hans": "内容已保存", "zh-Hant": "內容已儲存"],
        "Settings": ["zh-Hans": "设置", "zh-Hant": "設定"],
        "General": ["zh-Hans": "通用", "zh-Hant": "一般"],
        "About": ["zh-Hans": "关于", "zh-Hant": "關於"],
        "Quit": ["zh-Hans": "退出", "zh-Hant": "結束"],
        "Preferences": ["zh-Hans": "偏好设置", "zh-Hant": "偏好設定"],
        "Shortcut": ["zh-Hans": "快捷键", "zh-Hant": "快捷鍵"],
        "Display": ["zh-Hans": "显示", "zh-Hant": "顯示"],
        "Update": ["zh-Hans": "更新", "zh-Hant": "更新"],
        "Done": ["zh-Hans": "完成", "zh-Hant": "完成"],
        "Error": ["zh-Hans": "错误", "zh-Hant": "錯誤"],
        "Retry": ["zh-Hans": "重试", "zh-Hant": "重試"],
        "Success": ["zh-Hans": "成功", "zh-Hant": "成功"],
        "OK": ["zh-Hans": "确定", "zh-Hant": "確定"],
        // TitleBarView translations
        "Attachments": ["zh-Hans": "附件", "zh-Hant": "附件"],
        "No attachments": ["zh-Hans": "无附件", "zh-Hant": "無附件"],
        // OnboardingView translations
        "Previous": ["zh-Hans": "上一步", "zh-Hant": "上一步"],
        "Next Step": ["zh-Hans": "下一步", "zh-Hant": "下一步"],
        "Start Writedown": ["zh-Hans": "开始使用 Writedown", "zh-Hant": "開始使用 Writedown"],
        "Storage Location": ["zh-Hans": "存储位置", "zh-Hant": "儲存位置"],
        "Change Location": ["zh-Hans": "更改位置", "zh-Hant": "變更位置"],
        "Select Notes Directory": ["zh-Hans": "选择笔记目录", "zh-Hant": "選擇筆記目錄"],
        "From %@": ["zh-Hans": "来自 %@", "zh-Hant": "來自 %@"],
        "From %@ | %d chars": ["zh-Hans": "来自 %@ | %d 字符", "zh-Hant": "來自 %@ | %d 字元"],
        // Summarize.swift notifications
        "Maybe Like Captured": ["zh-Hans": "可能喜欢的内容已保存", "zh-Hant": "可能喜歡的內容已儲存"],
        // ContentView
        "Start writing...": ["zh-Hans": "开始写作...", "zh-Hant": "開始撰寫..."],
        // SettingsView - Sections and Labels
        "Updates": ["zh-Hans": "更新", "zh-Hant": "更新"],
        "Release Notes": ["zh-Hans": "发布说明", "zh-Hant": "發行說明"],
        "Send Feedback": ["zh-Hans": "发送反馈", "zh-Hant": "傳送回饋"],
        "Note Operations": ["zh-Hans": "笔记操作", "zh-Hant": "筆記操作"],
        "New Note": ["zh-Hans": "新建笔记", "zh-Hant": "新增筆記"],
        "Copy All": ["zh-Hans": "复制全部", "zh-Hant": "複製全部"],
        "Navigation": ["zh-Hans": "导航", "zh-Hant": "導覽"],
        "History": ["zh-Hans": "历史记录", "zh-Hant": "歷史紀錄"],
        "Storage": ["zh-Hans": "存储", "zh-Hant": "儲存"],
        "Location": ["zh-Hans": "位置", "zh-Hant": "位置"],
        "Auto-save interval": ["zh-Hans": "自动保存间隔", "zh-Hant": "自動儲存間隔"],
        "Editor": ["zh-Hans": "编辑器", "zh-Hant": "編輯器"],
        "Provider": ["zh-Hans": "提供方", "zh-Hant": "提供方"],
        "API Key": ["zh-Hans": "API Key", "zh-Hant": "API Key"],
        "Configured": ["zh-Hans": "已配置", "zh-Hant": "已配置"],
        "Required": ["zh-Hans": "必填", "zh-Hant": "必填"],
        "Enter your MiniMax API Key": ["zh-Hans": "填写你的 MiniMax API Key", "zh-Hant": "填寫你的 MiniMax API Key"],
        "Enter your MiniMax API Key first": ["zh-Hans": "请先填写 MiniMax API Key", "zh-Hant": "請先填寫 MiniMax API Key"],
        "AI features require your own MiniMax API key. Leave it blank to keep AI disabled.": ["zh-Hans": "AI 功能需要你自行提供 MiniMax API Key。留空时，AI 保持禁用。", "zh-Hant": "AI 功能需要你自行提供 MiniMax API Key。留空時，AI 保持停用。"],
        "Auto generate note titles": ["zh-Hans": "自动生成笔记标题", "zh-Hant": "自動產生筆記標題"],
        "Auto save important clipboard content": ["zh-Hans": "自动保存重要剪贴板内容", "zh-Hant": "自動儲存重要剪貼簿內容"],
        "Status": ["zh-Hans": "状态", "zh-Hant": "狀態"],
        // SettingsView - More items (duplicates removed: Preferences, Font, Double press Option key, Latest available)
        "Launch at login": ["zh-Hans": "开机启动", "zh-Hant": "開機啟動"],
        "Change...": ["zh-Hans": "更改...", "zh-Hant": "更改..."],
        "Wake Up": ["zh-Hans": "快速唤醒", "zh-Hant": "快速喚醒"],
        "Quick wake-up": ["zh-Hans": "快速唤醒", "zh-Hant": "快速喚醒"],
        "Double press Option key to toggle window": ["zh-Hans": "双击 Option 键切换窗口", "zh-Hant": "雙擊 Option 鍵切換視窗"],
        "Quick save": ["zh-Hans": "快速保存", "zh-Hant": "快速儲存"],
        "Downloading... %d%": ["zh-Hans": "正在下载... %d%", "zh-Hant": "正在下載... %d%"],
        "Checking...": ["zh-Hans": "检查中...", "zh-Hant": "檢查中..."],
        "Check Now": ["zh-Hans": "立即检查", "zh-Hant": "立即檢查"],
        "Previous attempt failed": ["zh-Hans": "上次尝试失败", "zh-Hant": "上次嘗試失敗"],
        "Support": ["zh-Hans": "支持", "zh-Hant": "支援"],
        "Writedown Feedback": ["zh-Hans": "Writedown 反馈", "zh-Hant": "Writedown 回饋"],
        "Update failed": ["zh-Hans": "更新失败", "zh-Hant": "更新失敗"],
        "Invalid download link": ["zh-Hans": "无效的下载链接", "zh-Hant": "無效的下載連結"],
        "New version available": ["zh-Hans": "新版本可用", "zh-Hant": "新版本可用"],
        "Later": ["zh-Hans": "稍后", "zh-Hant": "稍後"],
        "You're up to date!": ["zh-Hans": "已是最新版本！", "zh-Hant": "已是最新版本！"],
        "Failed to check for updates": ["zh-Hans": "检查更新失败", "zh-Hant": "檢查更新失敗"],
        "Theme": ["zh-Hans": "主题", "zh-Hant": "主題"],
        "New Version Available": ["zh-Hans": "新版本可用", "zh-Hant": "新版本可用"],
        "Restart to install": ["zh-Hans": "重启以安装", "zh-Hant": "重新啟動以安裝"],
        // More UI items
        "Copy Contents": ["zh-Hans": "复制内容", "zh-Hant": "複製內容"],
        "Share Contents": ["zh-Hans": "分享内容", "zh-Hant": "分享內容"],
        "Show in Finder": ["zh-Hans": "在访达中显示", "zh-Hant": "在 Finder 中顯示"],
        // Onboarding and other missing translations
        "AI, truly helpful": ["zh-Hans": "AI，真正有用", "zh-Hant": "AI，真正有用"],
        "Anywhere, with your custom shortcut.": ["zh-Hans": "随时随地，使用自定义快捷键。", "zh-Hant": "隨時隨地，使用自訂快捷鍵。"],
        "Click to install Update": ["zh-Hans": "点击安装更新", "zh-Hant": "點擊安裝更新"],
        "Delete": ["zh-Hans": "删除", "zh-Hant": "刪除"],
        "Delete Note": ["zh-Hans": "删除笔记", "zh-Hant": "刪除筆記"],
        "Designed for quick write-down": ["zh-Hans": "为快速记录而设计", "zh-Hant": "專為快速記錄而設計"],
        "Enter title": ["zh-Hans": "输入标题", "zh-Hant": "輸入標題"],
        "Help summarize & make plans.": ["zh-Hans": "帮助总结和制定计划。", "zh-Hant": "協助總結和制定計劃。"],
        "Quick wake-up shortcut": ["zh-Hans": "快速唤醒快捷键", "zh-Hant": "快速喚醒快捷鍵"],
        "Quickly access Writedown when you need it": ["zh-Hans": "在需要时快速访问 Writedown", "zh-Hant": "在需要時快速存取 Writedown"],
        "Ready to start your note-taking journey": ["zh-Hans": "准备开始您的笔记之旅", "zh-Hant": "準備開始您的筆記之旅"],
        "Search notes...": ["zh-Hans": "搜索笔记...", "zh-Hant": "搜尋筆記..."],
        "Set your preferred keyboard shortcut to quickly access Writedown from anywhere": ["zh-Hans": "设置您喜欢的键盘快捷键，随时随地快速访问 Writedown", "zh-Hant": "設定您偏好的鍵盤快捷鍵，隨時隨地快速存取 Writedown"],
        "Start at login": ["zh-Hans": "开机启动", "zh-Hant": "開機啟動"],
        "You're All Set!": ["zh-Hans": "一切准备就绪！", "zh-Hant": "一切準備就緒！"],
        // AI Agent related
        "Schedule Reminder": ["zh-Hans": "定时提醒", "zh-Hant": "定時提醒"],
        "Create Calendar Event": ["zh-Hans": "创建日历事件", "zh-Hant": "建立日曆事件"],
        "Text Editing": ["zh-Hans": "文本编辑", "zh-Hant": "文字編輯"],
        "Quick Note": ["zh-Hans": "快速笔记", "zh-Hant": "快速筆記"],
        "Unknown": ["zh-Hans": "未知", "zh-Hant": "未知"],
        "Today": ["zh-Hans": "今天", "zh-Hant": "今天"],
        "Tomorrow": ["zh-Hans": "明天", "zh-Hant": "明天"],
        "Remind you to \"%@\" at %@": ["zh-Hans": "在 %2$@ 提醒你「%1$@」", "zh-Hant": "在 %2$@ 提醒你「%1$@」"],
        "Create event \"%@\" at %@": ["zh-Hans": "在 %2$@ 创建活动「%1$@」", "zh-Hant": "在 %2$@ 建立活動「%1$@」"],
        "Create Reminder": ["zh-Hans": "创建提醒", "zh-Hant": "建立提醒"],
        "Create Event": ["zh-Hans": "创建事件", "zh-Hant": "建立事件"],
        "Edit Text": ["zh-Hans": "编辑文本", "zh-Hant": "編輯文字"],
        "AI Agent": ["zh-Hans": "AI 助理", "zh-Hant": "AI 助理"],
        "Title": ["zh-Hans": "标题", "zh-Hant": "標題"],
        "Time": ["zh-Hans": "时间", "zh-Hant": "時間"],
        "Confidence": ["zh-Hans": "置信度", "zh-Hant": "信心度"],
        "Suggestions": ["zh-Hans": "建议", "zh-Hant": "建議"],
        "Cancel": ["zh-Hans": "取消", "zh-Hant": "取消"],
        "Confirm": ["zh-Hans": "确认", "zh-Hant": "確認"],
        "AI Processing...": ["zh-Hans": "AI 处理中...", "zh-Hant": "AI 處理中..."],
        "No content to analyze": ["zh-Hans": "没有内容可分析", "zh-Hant": "沒有內容可分析"],
        "AI analysis failed": ["zh-Hans": "AI 分析失败", "zh-Hant": "AI 分析失敗"],
        "Intent not supported": ["zh-Hans": "不支持的意图", "zh-Hant": "不支援的意圖"],
        "Action completed": ["zh-Hans": "操作完成", "zh-Hant": "操作完成"],
        "Action failed": ["zh-Hans": "操作失败", "zh-Hant": "操作失敗"],
        "Reminder Created": ["zh-Hans": "提醒已创建", "zh-Hant": "提醒已建立"],
        "Event Created": ["zh-Hans": "事件已创建", "zh-Hant": "事件已建立"],
        "Scheduled for %@": ["zh-Hans": "安排在 %@", "zh-Hant": "安排在 %@"],
        "MiniMax API Key is required": ["zh-Hans": "MiniMax API Key 为必填项", "zh-Hant": "MiniMax API Key 為必填項"],
        "MiniMax API configuration is invalid": ["zh-Hans": "MiniMax API 配置无效", "zh-Hant": "MiniMax API 設定無效"],
        "MiniMax returned an invalid response": ["zh-Hans": "MiniMax 返回了无效响应", "zh-Hant": "MiniMax 回傳了無效回應"],
        "MiniMax request failed (%d)": ["zh-Hans": "MiniMax 请求失败（%d）", "zh-Hant": "MiniMax 請求失敗（%d）"],
        "MiniMax request failed (%d): %@": ["zh-Hans": "MiniMax 请求失败（%d）：%@", "zh-Hant": "MiniMax 請求失敗（%d）：%@"],
        "Permission to access Reminders was denied. Please enable it in System Settings.": ["zh-Hans": "提醒事项访问权限被拒绝。请在系统设置中启用。", "zh-Hant": "提醒事項存取權限被拒絕。請在系統設定中啟用。"],
        "No default calendar found for reminders.": ["zh-Hans": "未找到默认提醒日历。", "zh-Hant": "未找到預設提醒日曆。"],
        "The reminder could not be found.": ["zh-Hans": "找不到该提醒。", "zh-Hant": "找不到該提醒。"],
        "The event could not be found.": ["zh-Hans": "找不到该事件。", "zh-Hant": "找不到該事件。"],
        "Failed to save the reminder.": ["zh-Hans": "保存提醒失败。", "zh-Hant": "儲存提醒失敗。"]
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
    static let zhHant = Language(code: "zh-Hant", name: "繁體中文")

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
