//
//  ClaudeCodeTerminalWindow.swift
//  Writedown
//
//  Created by Claude Code on 1/25/26.
//

import SwiftUI

/// Updated ClaudeCodeOutputView using SwiftTerm
struct ClaudeCodeTerminalWindow: View {

    let noteContent: String?
    let noteTitle: String?
    let workingDirectory: URL

    @Environment(\.presentationMode) var presentationMode
    @StateObject private var service = SwiftTermService.shared
    @State private var selectedTheme: TerminalTheme = .vscode

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerBar

            // Terminal View
            SwiftTerminalView_Themed(
                noteContent: noteContent,
                noteTitle: noteTitle,
                workingDirectory: workingDirectory,
                theme: selectedTheme
            )

            // Footer
            footerBar
        }
        .frame(minWidth: 700, minHeight: 500)
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal.fill")
                .foregroundColor(.blue)
                .font(.system(size: 16))

            Text("Claude Code Terminal")
                .font(.headline)

            Spacer()

            // Theme selector
            Menu {
                Button("VS Code Dark") {
                    selectedTheme = .vscode
                }
                Button("Dracula") {
                    selectedTheme = .dracula
                }
                Button("One Dark") {
                    selectedTheme = .oneDark
                }
            } label: {
                Image(systemName: "paintpalette")
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24, height: 24)

            // Running indicator
            if service.isRunning {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                    Text("Running")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Close button
            Button(action: {
                service.cancel()
                presentationMode.wrappedValue.dismiss()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Footer Bar

    private var footerBar: some View {
        HStack {
            // Session info
            if let session = service.sessionInfo {
                HStack(spacing: 8) {
                    Image(systemName: "cpu")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text("Model: \(session.model)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider()
                        .frame(height: 12)

                    Image(systemName: "folder")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text(session.cwd)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                if service.isRunning {
                    Button("Cancel") {
                        service.cancel()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Preview

#if DEBUG
struct ClaudeCodeTerminalWindow_Previews: PreviewProvider {
    static var previews: some View {
        ClaudeCodeTerminalWindow(
            noteContent: "帮我分析这个项目",
            noteTitle: "测试笔记",
            workingDirectory: URL(fileURLWithPath: NSHomeDirectory())
        )
        .frame(width: 900, height: 700)
    }
}
#endif
