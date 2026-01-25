//
//  ClaudeTerminalDelegate.swift
//  Writedown
//
//  Created by Claude Code on 1/25/26.
//

import SwiftTerm
import Foundation
import AppKit

/// Delegate for handling terminal events and data transmission
class ClaudeTerminalDelegate: TerminalViewDelegate {

    weak var terminalView: ClaudeTerminalView?
    private var dataHandler: ((ArraySlice<UInt8>) -> Void)?

    init(terminalView: ClaudeTerminalView) {
        self.terminalView = terminalView
    }

    // MARK: - TerminalViewDelegate

    /// Send data to the running program (keyboard input, etc.)
    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        // Forward data to the handler if set
        dataHandler?(data)

        // Log for debugging
        if let text = String(bytes: data, encoding: .utf8) {
            print("[Terminal] Sending: \(text.debugDescription)")
        }
    }

    /// Terminal size changed
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        print("[Terminal] Size changed to \(newCols)x\(newRows)")

        // If we were managing a pty directly, we would send SIGWINCH here
        // For now, the process will handle its own terminal size
    }

    /// Scroll position changed
    func scrolled(source: TerminalView, position: Double) {
        // Can be used for custom scroll indicators
        // For now, no action needed
    }

    /// Set terminal title (from OSC 0, 1, 2)
    func setTerminalTitle(source: TerminalView, title: String) {
        print("[Terminal] Title: \(title)")

        // Could update window title here if needed
        DispatchQueue.main.async {
            if let window = source.window {
                window.title = "Claude Code - \(title)"
            }
        }
    }

    /// Icon title (from OSC 1)
    func setTerminalIconTitle(source: TerminalView, title: String) {
        // macOS doesn't use icon titles
    }

    /// Current directory update (from OSC 7)
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        if let dir = directory {
            print("[Terminal] Current directory: \(dir)")
        }
    }

    /// Bell/beep notification
    func bell(source: TerminalView) {
        NSSound.beep()
    }

    /// Request clipboard data for paste operation
    func clipboard(source: TerminalView) -> Data? {
        return NSPasteboard.general.data(forType: .string)
    }

    /// Copy data to clipboard
    func clipboardCopy(source: TerminalView, content: Data) {
        if let text = String(data: content, encoding: .utf8) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)

            print("[Terminal] Copied to clipboard: \(text.prefix(50))...")
        }
    }

    /// Range of lines changed (for rendering optimization)
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        // SwiftTerm handles rendering internally
        // This is mainly for debugging or custom rendering
    }

    /// Is the terminal buffer in alternative screen mode?
    func isProcessTrusted(source: TerminalView) -> Bool {
        // Return true to allow all operations
        return true
    }

    /// Mouse mode changed
    func mouseModeChanged(source: TerminalView) {
        // Handle mouse mode changes if needed
    }

    // MARK: - Custom Methods

    /// Set a handler for outgoing data
    /// - Parameter handler: Closure to handle data sent from terminal
    func setDataHandler(_ handler: @escaping (ArraySlice<UInt8>) -> Void) {
        self.dataHandler = handler
    }
}
