//
//  OpenCodeTerminalWindow.swift
//  Writedown
//
//  Created by AI Agent on 1/25/26.
//

import SwiftUI

struct OpenCodeTerminalWindow: View {
    let noteContent: String?
    let noteTitle: String?
    let workingDirectory: URL

    var body: some View {
        OpenCodeOutputView()
            .task {
                // Start execution when window appears
                if OpenCodeService.shared.state == .idle {
                    do {
                        try await OpenCodeService.shared.execute(
                            noteContent: noteContent,
                            noteTitle: noteTitle,
                            workingDirectory: workingDirectory
                        )
                    } catch {
                        print("Failed to start OpenCode: \(error)")
                    }
                }
            }
            .frame(minWidth: 600, minHeight: 400)
    }
}

#Preview {
    OpenCodeTerminalWindow(
        noteContent: "Test content",
        noteTitle: "Test Note",
        workingDirectory: URL(fileURLWithPath: "/tmp")
    )
}
