// import Foundation
// import SwiftUI

// struct SettingsListView: View {
//     @Environment(\.dismiss) private var dismiss
//     @Environment(\.colorScheme) private var colorScheme

//     let onSettings: () -> Void
//     let title: String?

//     private func generateObsidianURI(from title: String) -> String? {
//         guard !title.isEmpty else { return nil }
//         let weekFolder = FileManager.shared.currentWeekDirectory?.lastPathComponent ?? ""
//         let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
//         return "obsidian://open?vault=obsidian&file=Float%2F\(weekFolder)%2F\(encodedTitle)"
//     }

//     private func openInFinder() {
//         guard let notesDirectory = FileManager.shared.notesDirectory else {
//             print("Could not access notes directory")
//             return
//         }

//         NSWorkspace.shared.selectFile(
//             nil,
//             inFileViewerRootedAtPath: notesDirectory.path
//         )
//     }

//     var body: some View {
//         VStack(alignment: .leading, spacing: 0) {
//             ForEach(SettingsItem.allCases) { item in
//                 HoverButton(
//                     action: {
//                         handleAction(item)
//                         dismiss()
//                     },
//                     label: {
//                         HStack(spacing: 6) {
//                             if item == .openInObsidian {
//                                 Image("obsidian-icon")
//                                     .resizable()
//                                     .aspectRatio(contentMode: .fit)
//                                     .frame(width: 16, height: 16)
//                             } else if item == .showAll {
//                                 Image("finder-icon")
//                                     .resizable()
//                                     .aspectRatio(contentMode: .fit)
//                                     .frame(width: 16, height: 16)
//                             } else {
//                                 Image(systemName: item.icon)
//                                     .frame(width: 16)
//                                     .foregroundColor(.primary)
//                                     .opacity(0.9)
//                             }
//                             Text(item.title)
//                                 .foregroundColor(.primary)
//                         }
//                         .foregroundColor(.primary)
//                         .frame(maxWidth: .infinity, alignment: .leading)
//                         .padding(.horizontal, 6)
//                         .padding(.vertical, 4)
//                     }
//                     //  .padding(.horizontal, 6)
//                 )

//                 // Add rectangle separator after Show All
//                 if item == .showAll {
//                     Rectangle()
//                         .fill(Color(NSColor.separatorColor))
//                         .frame(height: 4)
//                         // .padding(.vertical, 4)
//                 }
//             }
//         }
//         // .padding(.vertical, 6)
//         .frame(width: 180)
//         .background(Color(NSColor.windowBackgroundColor))
//     }

//     private func handleAction(_ item: SettingsItem) {
//         switch item {
//         case .openInObsidian:
//             if let title = title, let uri = generateObsidianURI(from: title) {
//                 NSWorkspace.shared.open(URL(string: uri)!)
//             }
//         case .showAll:
//             openInFinder()
//         case .settings:
//             onSettings()
//         }
//     }
// }

// struct HoverButton: View {
//     let action: () -> Void
//     let label: () -> AnyView
//     @State private var isHovered = false
//     @Environment(\.colorScheme) private var colorScheme

//     init(action: @escaping () -> Void, @ViewBuilder label: @escaping () -> some View) {
//         self.action = action
//         self.label = { AnyView(label()) }
//     }

//     var body: some View {
//         Button(action: action) {
//             label()
//                 .contentShape(Rectangle())
//         }
//         .buttonStyle(.plain)
//         .padding(.horizontal, 4)
//         .padding(.vertical, 6)
//         .background(
//             RoundedRectangle(cornerRadius: 0)
//                 .fill(
//                     isHovered
//                         ? (colorScheme == .dark ? Color(white: 0.3) : Color(white: 0.85))
//                         : Color.clear)
//         )
//         .onHover { hovering in
//             isHovered = hovering
//             if hovering {
//                 NSCursor.pointingHand.push()
//             } else {
//                 NSCursor.pop()
//             }
//         }
//     }
// }

// enum SettingsItem: Int, CaseIterable, Identifiable {
//     case openInObsidian
//     case showAll
//     case settings

//     var id: Int { rawValue }

//     var title: String {
//         switch self {
//         case .openInObsidian:
//             return "Open in Obsidian"
//         case .showAll:
//             return "Show in Finder"
//         case .settings:
//             return "Settings"
//         }
//     }

//     var icon: String {
//         switch self {
//         case .settings:
//             return "gear"
//         case .openInObsidian:
//             return "link.circle.fill"
//         case .showAll:
//             return "folder"
//         }
//     }
// }

import Foundation
import SwiftUI

struct SettingsListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let onSettings: () -> Void
    let title: String?

    private func generateObsidianURI(from title: String) -> String? {
        guard !title.isEmpty else { return nil }
        let weekFolder = FileManager.shared.currentWeekDirectory?.lastPathComponent ?? ""
        let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        return "obsidian://open?vault=obsidian&file=Float%2F\(weekFolder)%2F\(encodedTitle)"
    }

    private func openInFinder() {
        guard let notesDirectory = FileManager.shared.notesDirectory else {
            print("Could not access notes directory")
            return
        }

        NSWorkspace.shared.selectFile(
            nil,
            inFileViewerRootedAtPath: notesDirectory.path
        )
    }

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
                            // if item == .openInObsidian {
                            //     Image("obsidian-icon")
                            //         .resizable()
                            //         .aspectRatio(contentMode: .fit)
                            //         .frame(width: 16, height: 16)
                            // } else if item == .showAll {
                            //     Image("finder-icon")
                            //         .resizable()
                            //         .aspectRatio(contentMode: .fit)
                            //         .frame(width: 16, height: 16)
                            // } else {
                            //     Image(systemName: item.icon)
                            //         .frame(width: 16)
                            //         .foregroundColor(.primary)
                            //         .opacity(0.9)
                            // }
                            Text(item.title)
                                .foregroundColor(.primary)
                                .padding(.leading, 4)
                        }
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                )
                .padding(.horizontal, 4)

                // Add rectangle separator after Show All
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
        .frame(width: 160)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func handleAction(_ item: SettingsItem) {
        switch item {
        case .openInObsidian:
            if let title = title, let uri = generateObsidianURI(from: title) {
                NSWorkspace.shared.open(URL(string: uri)!)
            }
        case .showAll:
            openInFinder()
        case .settings:
            onSettings()
        }
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
    case openInObsidian
    case showAll
    case settings

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .openInObsidian:
            return "Open in Obsidian"
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
        case .openInObsidian:
            return "link.circle.fill"
        case .showAll:
            return "folder"
        }
    }
}
