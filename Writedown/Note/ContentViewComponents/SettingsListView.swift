import Foundation
import SwiftUI

struct SettingsListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let onSettings: () -> Void
    let onCopy: () -> Void
    let onShare: () -> Void
    let title: String?

    // private func generateObsidianURI(from title: String) -> String? {
    //     guard !title.isEmpty else { return nil }
    //     let weekFolder = FileManager.shared.currentWeekDirectory?.lastPathComponent ?? ""
    //     let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
    //     return "obsidian://open?vault=obsidian&file=Float%2F\(weekFolder)%2F\(encodedTitle)"
    // }

    private func openInFinder() {
        guard let notesDirectory = FileManager.shared.currentWeekDirectory else {
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
            ForEach(SettingsItem.allCases) { item in
                HoverButton(
                    action: {
                        handleAction(item)
                        dismiss()
                    },
                    label: {
                        HStack(spacing: 6) {
                            Text(item.title)
                                .foregroundColor(.primary)
                                .padding(.leading, 4)

                            Spacer()

                            if let shortcut = item.shortcut {
                                HStack(spacing: 2) {
                                    ForEach(shortcut.map(String.init), id: \.self) { char in
                                        Text(char)
                                            .font(.system(size: 11))
                                            .frame(width: 18, height: 18)
                                            .background(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(
                                                        Color(NSColor.tertiaryLabelColor).opacity(
                                                            0.3))
                                            )
                                    }
                                }
                            }
                        }
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                )
                .padding(.horizontal, 4)

                if item == .copyContents {
                    Rectangle()
                        .fill(Color(NSColor.separatorColor))
                        .frame(height: 1)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 12)
                }

                if item == .showAll {
                    Rectangle()
                        .fill(Color(NSColor.separatorColor))
                        .frame(height: 1)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 12)
                }
            }
        }
        .padding(.vertical, 6)
        .frame(width: 200)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func handleAction(_ item: SettingsItem) {
        switch item {
        case .showAll:
            openInFinder()
        case .settings:
            onSettings()
        case .copyContents:
            onCopy()
        case .shareContents:
            onShare()
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
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isHovered
                            ? (colorScheme == .dark ? Color(white: 0.3) : Color(white: 0.85))
                            : Color.clear)
            )
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
        // case openInObsidian
        //    case openInFeishu
        case copyContents
        case shareContents
        case showAll
        case settings

        var id: Int { rawValue }

        var title: String {
            switch self {
            // case .openInObsidian:
            //     return "Open in Obsidian"
            //        case .openInFeishu:
            //            return "Open in Feishu"
            case .copyContents:
                return "Copy Contents"
            case .shareContents:
                return "Share Contents"
            case .showAll:
                return "Show in Finder"
            case .settings:
                return "Settings"
            }
        }

        var icon: String {
            switch self {
            case .settings:
                return "gear"
            // case .openInObsidian:
            //     return "link.circle.fill"
            //        case .openInFeishu:
            //            return "link.circle.fill"
            case .showAll:
                return "folder"
            case .copyContents:
                return "copy"
            case .shareContents:
                return "square.and.arrow.up"
            }
        }

        var shortcut: String? {
            switch self {
            case .copyContents:
                return "⌘⇧C"
            case .shareContents:
                return nil
            case .settings:
                return "⌘,"
            default:
                return nil
            }
        }
    }
}
