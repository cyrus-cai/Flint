//
//  ClaudeCodeTerminalWindow.swift
//  Writedown
//
//  Created by Claude Code on 1/25/26.
//

import SwiftUI

struct ClaudeCodeTerminalWindow: View {

    let noteContent: String?
    let noteTitle: String?
    let workingDirectory: URL

    @Environment(\.presentationMode) var presentationMode
    @StateObject private var service = SwiftTermService.shared
    @AppStorage(AppStorageKeys.terminalTheme) private var themeName: String = AppDefaults.terminalTheme

    private var selectedTheme: TerminalTheme {
        TerminalTheme.withName(themeName)
    }

    var body: some View {
        ZStack {
            Color(nsColor: selectedTheme.background).ignoresSafeArea()
            
            SwiftTerminalView_Themed(
                noteContent: noteContent,
                noteTitle: noteTitle,
                workingDirectory: workingDirectory,
                theme: selectedTheme
            )
            .padding(16)

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
        .frame(minWidth: 500, minHeight: 350)
    }

    // MARK: - Header Overlay

    private var headerOverlay: some View {
        HStack(spacing: 10) {
            if service.isRunning {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                    Text("Running")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(12)
    }


    // MARK: - Footer Overlay

    private var footerOverlay: some View {
        HStack(spacing: 10) {
            if let session = service.sessionInfo {
                HStack(spacing: 5) {
                    Image(systemName: "cpu")
                        .font(.system(size: 10))
                    Text(session.model)
                        .font(.system(size: 10))
                }
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            if service.isRunning {
                Button(action: {
                    service.cancel()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 8))
                        Text("Cancel")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
    }
}

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
