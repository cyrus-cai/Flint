//
//  ClaudeCodeTerminalWindowController.swift
//  Writedown
//
//  Created by Claude Code on 1/25/26.
//

import AppKit
import SwiftUI

/// 独立的窗口控制器，用于展示 Claude Code Terminal
/// 窗口会居中显示，解决使用 sheet 时位置太靠右的问题
class ClaudeCodeTerminalWindowController: NSWindowController {
    static var shared: ClaudeCodeTerminalWindowController?

    private let noteContent: String?
    private let noteTitle: String?
    private let workingDirectory: URL

    init(noteContent: String?, noteTitle: String?, workingDirectory: URL) {
        self.noteContent = noteContent
        self.noteTitle = noteTitle
        self.workingDirectory = workingDirectory

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)

        configureWindow()
        setupContentView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureWindow() {
        guard let window = window else { return }

        window.title = "Claude Code Terminal"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = true
        window.backgroundColor = NSColor(red: 0x1E/255.0, green: 0x1E/255.0, blue: 0x1E/255.0, alpha: 1.0)
        window.hasShadow = true

        // 设置窗口最小和最大尺寸
        window.minSize = NSSize(width: 500, height: 350)
        window.maxSize = NSSize(width: 1600, height: 1200)

        // 居中显示
        window.center()

        // 窗口层级设置
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // 应用当前的外观设置
        if let appearanceMode = AppearanceMode(
            rawValue: UserDefaults.standard.string(forKey: "appearanceMode") ?? "System"
        ) {
            switch appearanceMode {
            case .system:
                window.appearance = nil
            case .light:
                window.appearance = NSAppearance(named: .aqua)
            case .dark:
                window.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }

    private func setupContentView() {
        let terminalView = ClaudeCodeTerminalWindow(
            noteContent: noteContent,
            noteTitle: noteTitle,
            workingDirectory: workingDirectory
        )

        let hostingView = NSHostingView(rootView: terminalView)
        window?.contentView = hostingView
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 便捷方法：显示 Claude Code Terminal 窗口
    static func show(noteContent: String?, noteTitle: String?, workingDirectory: URL) {
        // 如果已有窗口，先关闭
        shared?.close()

        let controller = ClaudeCodeTerminalWindowController(
            noteContent: noteContent,
            noteTitle: noteTitle,
            workingDirectory: workingDirectory
        )
        shared = controller
        controller.showWindow(nil)
    }
}
