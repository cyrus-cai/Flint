//
//  SwiftTerminalView.swift
//  Writedown
//
//  Created by Claude Code on 1/25/26.
//

import SwiftUI
import SwiftTerm

/// SwiftUI wrapper for ClaudeTerminalView
struct SwiftTerminalView: NSViewRepresentable {

    let noteContent: String?
    let noteTitle: String?
    let workingDirectory: URL

    @StateObject private var service = SwiftTermService.shared

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> ClaudeTerminalView {
        let terminalView = service.createTerminalView(
            noteContent: noteContent,
            noteTitle: noteTitle,
            workingDirectory: workingDirectory
        )

        // Apply default theme
        terminalView.applyTheme(.vscode)

        return terminalView
    }

    func updateNSView(_ nsView: ClaudeTerminalView, context: Context) {
        // Update if needed when SwiftUI state changes
        // For now, terminal content is managed by the service
    }

    static func dismantleNSView(_ nsView: ClaudeTerminalView, coordinator: ()) {
        // Cleanup when view is removed
        // The service will handle process termination
    }
}

// MARK: - Themed Variant

struct SwiftTerminalView_Themed: NSViewRepresentable {

    let noteContent: String?
    let noteTitle: String?
    let workingDirectory: URL
    let theme: TerminalTheme

    @StateObject private var service = SwiftTermService.shared

    func makeNSView(context: Context) -> ClaudeTerminalView {
        let terminalView = service.createTerminalView(
            noteContent: noteContent,
            noteTitle: noteTitle,
            workingDirectory: workingDirectory
        )

        // Apply custom theme
        terminalView.applyTheme(theme)

        return terminalView
    }

    func updateNSView(_ nsView: ClaudeTerminalView, context: Context) {
        // Apply theme if changed
        nsView.applyTheme(theme)
    }

    static func dismantleNSView(_ nsView: ClaudeTerminalView, coordinator: ()) {
        // Cleanup
    }
}

// MARK: - Previews

#if DEBUG
struct SwiftTerminalView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 0) {
            // Default theme
            SwiftTerminalView(
                noteContent: "帮我分析这个项目的结构",
                noteTitle: "测试笔记",
                workingDirectory: URL(fileURLWithPath: NSHomeDirectory())
            )
            .frame(height: 400)

            Divider()

            // Dracula theme
            SwiftTerminalView_Themed(
                noteContent: "测试 Dracula 主题",
                noteTitle: "主题测试",
                workingDirectory: URL(fileURLWithPath: NSHomeDirectory()),
                theme: .dracula
            )
            .frame(height: 400)
        }
        .frame(width: 900, height: 800)
    }
}
#endif
