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
    let onDelete: () -> Void
    let onTestSwiftTerm: () -> Void  // 🧪 SwiftTerm 测试回调
    let title: String?
    let isEmpty: Bool

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
    
    private func installHyperNoteSkill() {
        // Defer to next runloop to avoid "Publishing changes from within view updates" warning
        DispatchQueue.main.async {
            let notesPath = LocalFileManager.shared.baseDirectory?.path ?? "~/Documents/Writedown"

            DispatchQueue.global(qos: .userInitiated).async {
            // Get current week folder
            let calendar = Calendar(identifier: .iso8601)
            let weekOfYear = calendar.component(.weekOfYear, from: Date())
            let yearForWeek = calendar.component(.yearForWeekOfYear, from: Date())
            let currentWeek = String(format: "%dW%02d", yearForWeek, weekOfYear)
            let currentWeekPath = "\(notesPath)/\(currentWeek)"

            let skillContent = """
---
name: hypernote-manage-notes
description: Guide Claude to operate HyperNote notes - create, read, update, delete, search, AI operations
---

# hypernote-manage-notes

## Notes Directory

**Notes path:** `\(notesPath)`

**Current week folder:** `\(currentWeekPath)`

### Directory Structure

```
\(notesPath)/
├── 2026W03/
│   ├── Note Title.md
│   └── Another Note.md
├── \(currentWeek)/      <-- current week
└── ...
```

## Note Format

Notes may have optional metadata at the top:

```markdown
<!-- Source: AppName -->
<!-- Type: MaybeLike -->
Actual note content here...
```

When creating notes, you can omit metadata - just write plain markdown content.

## Common Operations

### 1. List Recent Notes

```bash
# 10 most recent notes
find "\(notesPath)" -name "*.md" -type f -exec stat -f "%m %N" {} \\; | sort -rn | head -10 | cut -d' ' -f2-
```

### 2. Search Notes

```bash
# By content
grep -r "keyword" "\(notesPath)"

# By filename
find "\(notesPath)" -iname "*keyword*.md"
```

### 3. Create Note

Use Write tool directly:
```
\(currentWeekPath)/Note Title.md
```

### 4. Read Note

Use Read tool with full path.

### 5. Update Note

Use Edit tool with full path.

### 6. Delete Note

```bash
rm "\(notesPath)/\(currentWeek)/unwanted-note.md"
```

### 7. Merge Multiple Notes

When user asks to organize/merge notes:
1. Read all target notes
2. Create a new consolidated note with organized content
3. Delete the original fragmented notes

## Rules

- Notes are organized by ISO week folders (e.g., \(currentWeek))
- Only delete individual .md files, never delete week folders
- Note filenames should be descriptive (used as title)
"""

            let fileManager = FileManager.default
            let homeDir = fileManager.homeDirectoryForCurrentUser
            let claudeSkillsDir = homeDir.appendingPathComponent(".claude/skills/hypernote-manage-notes")

            do {
                try fileManager.createDirectory(at: claudeSkillsDir, withIntermediateDirectories: true)

                let skillFilePath = claudeSkillsDir.appendingPathComponent("SKILL.md")
                try skillContent.write(to: skillFilePath, atomically: true, encoding: .utf8)

                DispatchQueue.main.async {
                    let notification = NSUserNotification()
                    notification.title = "Skill Installed"
                    notification.informativeText = "HyperNote Manage Notes skill has been installed to ~/.claude/skills/"
                    notification.soundName = NSUserNotificationDefaultSoundName
                    NSUserNotificationCenter.default.deliver(notification)
                }

                print("✅ Skill installed successfully at: \(skillFilePath.path)")
            } catch {
                print("❌ Failed to install skill: \(error)")

                DispatchQueue.main.async {
                    let notification = NSUserNotification()
                    notification.title = "Skill Installation Failed"
                    notification.informativeText = error.localizedDescription
                    NSUserNotificationCenter.default.deliver(notification)
                }
            }
            }
        }
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
            ForEach(SettingsItem.allCases.filter { item in
                // Filter out new version item if not available
                if item == .newVersionAvailable && !updateManager.newVersionAvailable {
                    return false
                }
                // Filter out delete note if content is empty
                if item == .deleteNote && isEmpty {
                    return false
                }
                return true
            }) { item in
                HoverButton(
                    action: {
                        handleAction(item)
                        dismiss()
                    },
                    label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.icon)
                                .font(.system(size: 13))
                                .foregroundColor(item == .deleteNote ? .red : .primary)
                                .frame(width: 14)

                            Text(item.title)
                                .foregroundColor(item == .deleteNote ? .red : .primary)
                                .padding(.leading, 2)
                                .fixedSize()

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
                            } else {
                                Spacer()
                                    .frame(height: 18)
                            }
                        }
                        .foregroundColor(.primary)
                        .frame(height: 18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                )
                .padding(.horizontal, 8)

                if item == .shareContents || item == .deleteNote {
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
            UpdateManager.shared.installUpdatePackage()
        case .showAll:
            openInFinder()
        case .addSkill:
            installHyperNoteSkill()
        case .testSwiftTerm:
            onTestSwiftTerm()
        case .settings:
            onSettings()
        case .deleteNote:
            onDelete()
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
        case deleteNote
        case showAll
        case addSkill
        case testSwiftTerm  // 🧪 SwiftTerm 测试
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
            case .deleteNote:
                return L("Delete Note")
            case .addSkill:
                return L("Add as Claude Code skill")
            case .testSwiftTerm:
                return "Test SwiftTerm"
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
            case .deleteNote:
                return "trash"
            case .copyContents:
                return "doc.on.doc"
            case .shareContents:
                return "square.and.arrow.up"
            case .newVersionAvailable:
                return "arrow.up.circle.fill"
            case .addSkill:
                return "puzzlepiece.extension"
            case .testSwiftTerm:
                return "terminal.fill"
            }
        }

        var shortcut: String? {
            switch self {
            case .copyContents:
                return "⌘⇧C"
            case .shareContents:
                return "⌘⇧S"
            case .deleteNote:
                return nil
            case .settings:
                return nil
            case .addSkill:
                return nil
            case .testSwiftTerm:
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
