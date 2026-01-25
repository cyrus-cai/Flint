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
        ZStack {
            SwiftTerminalView_Themed(
                noteContent: noteContent,
                noteTitle: noteTitle,
                workingDirectory: workingDirectory,
                theme: selectedTheme
            )

            VStack {
                HStack {
                    Spacer()
                    headerOverlay
                }
                
                Spacer()
                
                HStack {
                    footerOverlay
                    Spacer()
                }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }

    // MARK: - Header Overlay

    private var headerOverlay: some View {
        HStack(spacing: 8) {
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
                    .foregroundColor(.white.opacity(0.7))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20, height: 20)

            if service.isRunning {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 14, height: 14)
            }

            Button(action: {
                service.cancel()
                presentationMode.wrappedValue.dismiss()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.7))
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(8)
    }

    // MARK: - Footer Overlay

    private var footerOverlay: some View {
        HStack(spacing: 8) {
            if let session = service.sessionInfo {
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.caption2)
                    Text(session.model)
                        .font(.caption2)
                }
                .foregroundColor(.white.opacity(0.6))
            }

            if service.isRunning {
                Button("Cancel") {
                    service.cancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(8)
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
