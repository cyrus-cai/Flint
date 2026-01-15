import Foundation
import SwiftUI

struct SettingsListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    // 监听全局更新状态
    @ObservedObject private var updateManager = UpdateManager.shared

    let onSettings: () -> Void
    let onCopy: () -> Void
    let onShare: () -> Void
    let title: String?

    // private func generateObsidianURI(from title: String) -> String? {
    //     guard !title.isEmpty else { return nil }
    //     let weekFolder = LocalFileManager.shared.currentWeekDirectory?.lastPathComponent ?? ""
    //     let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
    //     return "obsidian://open?vault=obsidian&file=Float%2F\(weekFolder)%2F\(encodedTitle)"
    // }

    private func openInFinder() {
        guard let notesDirectory = LocalFileManager.shared.currentWeekDirectory else {
            print("Could not access notes directory")
            return
        }

        NSWorkspace.shared.selectFile(
            nil,
            inFileViewerRootedAtPath: notesDirectory.path
        )
    }

    //    private func generateFeishuURL(from title: String) -> String? {
    //        guard !title.isEmpty else { return nil }
    //        guard let documentId = UserDefaults.standard.string(forKey: "feishu_doc_\(title)") else {
    //            return nil
    //        }
    //        return "https://feishu.cn/docx/\(documentId)"
    //    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(SettingsItem.allCases.filter { $0 != .newVersionAvailable || updateManager.newVersionAvailable }) { item in
                HoverButton(
                    action: {
                        handleAction(item)
                        dismiss()
                    },
                    label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.icon)
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                                .frame(width: 14)

                            Text(item.title)
                                .foregroundColor(.primary)
                                .padding(.leading, 2)

                            Spacer()

                            if let shortcut = item.shortcut {
                                HStack(spacing: 2) {
                                    ForEach(shortcut.map(String.init), id: \.self) { char in
                                        Text(char)
                                            .font(.system(size: 11))
                                            .frame(width: 18, height: 18)
                                            .background(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(Color(NSColor.tertiaryLabelColor).opacity(0.3))
                                            )
                                    }
                                }
                            }
                        }
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                )
                .padding(.horizontal, 8)

                if item == .shareContents || item == .showAll {
                    Rectangle()
                        .fill(Color(NSColor.separatorColor))
                        .frame(height: 1)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 12)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(width: 220)
        // macOS 26+: 不设置背景，让原生 popover 的 Liquid Glass 效果显示
        // macOS 15-25: 使用窗口背景色
        .modifier(PopoverBackgroundModifier())
    }

    private func handleAction(_ item: SettingsItem) {
        switch item {
        case .copyContents:
            onCopy()
        case .shareContents:
            onShare()
        case .newVersionAvailable:
            // 点击新版本条目后调用更新安装方法
            UpdateManager.shared.installUpdatePackage()
        case .showAll:
            openInFinder()
        case .settings:
            onSettings()
        }
    }

    struct HoverButton: View {
        let action: () -> Void
        let label: () -> AnyView
        @State private var isHovered = false
        @Environment(\.colorScheme) private var colorScheme

        init(action: @escaping () -> Void, @ViewBuilder label: @escaping () -> some View) {
            self.action = action
            self.label = { AnyView(label()) }
        }

        var body: some View {
            Button(action: action) {
                label()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .modifier(HoverButtonBackgroundModifier(isHovered: isHovered, colorScheme: colorScheme))
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
    }

    enum SettingsItem: Int, CaseIterable, Identifiable {
        case copyContents
        case shareContents
        case showAll
        case newVersionAvailable
        case settings

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .copyContents:
                return L("Copy Contents")
            case .shareContents:
                return L("Share Contents")
            case .newVersionAvailable:
                return L("Click to install Update")
            case .showAll:
                return L("Show in Finder")
            case .settings:
                return L("Settings")
            }
        }

        var icon: String {
            switch self {
            case .settings:
                return "gear"
            case .showAll:
                return "folder"
            case .copyContents:
                return "doc.on.doc"
            case .shareContents:
                return "square.and.arrow.up"
            case .newVersionAvailable:
                return "arrow.up.circle.fill"
            }
        }

        var shortcut: String? {
            switch self {
            case .copyContents:
                return "⌘⇧C"
            case .shareContents:
                return "⌘⇧S"
            case .settings:
                return nil
            default:
                return nil
            }
        }
    }
}

// MARK: - Popover Background Modifier
/// On macOS 26+, removes background to let native Liquid Glass popover effect show through
/// On earlier versions, uses window background color
private struct PopoverBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            // macOS 26+: 透明背景，让原生 Liquid Glass 效果显示
            content
        } else {
            // macOS 15-25: 使用窗口背景色
            content.background(Color(NSColor.windowBackgroundColor))
        }
    }
}

// MARK: - Hover Button Background Modifier
/// On macOS 26+, uses native glassEffect for hover state
/// On earlier versions, uses colored background
private struct HoverButtonBackgroundModifier: ViewModifier {
    let isHovered: Bool
    let colorScheme: ColorScheme
    
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            // macOS 26+: 悬停时使用原生 Liquid Glass 效果
            if isHovered {
                content
                    .glassEffect(in: .rect(cornerRadius: 8))
            } else {
                content
            }
        } else {
            // macOS 15-25: 使用传统背景
            content
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            isHovered
                                ? (colorScheme == .dark ? Color(white: 0.3) : Color(white: 0.85))
                                : Color.clear)
                )
        }
    }
}
