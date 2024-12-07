import SwiftUI
import Foundation

struct SettingsListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let onRename: () -> Void
    let onDelete: () -> Void
    let onSettings: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsItem.allCases) { item in
                if item == .settings  {
                    HoverButton(
                        action: {
                            handleAction(item)
                            dismiss()
                        },
                        label: {
                            HStack(spacing: 6) {
                                Image(systemName: item.icon)
                                    .frame(width: 16)
                                    .foregroundColor(item == .delete ? .red : .primary)
                                    .opacity(0.9)
                                Text(item.title)
                                    .foregroundColor(item == .delete ? .red : .primary)
                            }
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    )
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)

        .frame(width: 160)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func handleAction(_ item: SettingsItem) {
        switch item {
        case .rename:
            onRename()
        case .delete:
            onDelete()
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
                .fill(isHovered ?
                    (colorScheme == .dark ? Color(white: 0.3) : Color(white: 0.85)) :
                    Color.clear)
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

class SettingsViewModel: ObservableObject {
    let fileURL: URL
    
    init(fileURL: URL) {
        self.fileURL = fileURL
    }
    
    func deleteNote() {
        do {
            try Foundation.FileManager.default.removeItem(at: fileURL)
        } catch {
            print("Error deleting note: \(error)")
        }
    }
}

enum SettingsItem: Int, CaseIterable, Identifiable {
    case rename
    case delete
    case settings
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .rename:
            return "Rename"
        case .delete:
            return "Delete"
        case .settings:
            return "Settings"
        }
    }
    
    var icon: String {
        switch self {
        case .rename:
            return "pencil"
        case .delete:
            return "trash"
        case .settings:
            return "gear"
        }
    }
}
