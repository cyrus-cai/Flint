//
//  ClaudeTerminalView.swift
//  Writedown
//
//  Created by Claude Code on 1/25/26.
//

import SwiftTerm
import AppKit

/// Custom TerminalView configured for Claude Code output
class ClaudeTerminalView: TerminalView {

    weak var terminalDelegate: ClaudeTerminalDelegate?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupTerminal()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTerminal()
    }

    // MARK: - Setup

    private func setupTerminal() {
        // Configure terminal size (will be adjusted by container)
        let terminal = getTerminal()
        terminal.resize(cols: 120, rows: 40)

        // Enable mouse reporting for selection
        allowMouseReporting = true

        // Configure scrolling
        if let scrollView = enclosingScrollView {
            scrollView.hasVerticalScroller = true
            scrollView.autohidesScrollers = true
        }
    }

    // MARK: - Convenience Methods

    /// Feed colored text using ANSI escape codes
    /// - Parameters:
    ///   - text: Text to display
    ///   - color: ANSI color to use
    func feedColored(text: String, color: ANSIColor) {
        let ansiText = "\(color.code)\(text)\u{001B}[0m"
        feed(text: ansiText)
    }

    /// Feed text with bold formatting
    /// - Parameter text: Text to display in bold
    func feedBold(text: String) {
        let boldText = "\u{001B}[1m\(text)\u{001B}[0m"
        feed(text: boldText)
    }

    /// Feed text with dim (faint) formatting
    /// - Parameter text: Text to display dimmed
    func feedDim(text: String) {
        let dimText = "\u{001B}[2m\(text)\u{001B}[0m"
        feed(text: dimText)
    }

    /// Clear the terminal screen
    func clearScreen() {
        feed(text: "\u{001B}[2J\u{001B}[H")
    }

    /// Scroll to bottom
    func scrollToBottom() {
        let terminal = getTerminal()
        let buffer = terminal.buffer
        scroll(toPosition: 1.0)
    }

    // MARK: - Keyboard Input Override

    override func keyDown(with event: NSEvent) {
        // For now, pass through to default behavior
        // In future, we can add custom key handling for shortcuts
        super.keyDown(with: event)
    }
}

// MARK: - ANSI Color Helper

enum ANSIColor {
    case black
    case red
    case green
    case yellow
    case blue
    case magenta
    case cyan
    case white
    case gray
    case brightRed
    case brightGreen
    case brightYellow
    case brightBlue
    case brightMagenta
    case brightCyan
    case brightWhite

    var code: String {
        switch self {
        case .black:         return "\u{001B}[30m"
        case .red:           return "\u{001B}[31m"
        case .green:         return "\u{001B}[32m"
        case .yellow:        return "\u{001B}[33m"
        case .blue:          return "\u{001B}[34m"
        case .magenta:       return "\u{001B}[35m"
        case .cyan:          return "\u{001B}[36m"
        case .white:         return "\u{001B}[37m"
        case .gray:          return "\u{001B}[90m"
        case .brightRed:     return "\u{001B}[91m"
        case .brightGreen:   return "\u{001B}[92m"
        case .brightYellow:  return "\u{001B}[93m"
        case .brightBlue:    return "\u{001B}[94m"
        case .brightMagenta: return "\u{001B}[95m"
        case .brightCyan:    return "\u{001B}[96m"
        case .brightWhite:   return "\u{001B}[97m"
        }
    }
}

// MARK: - Terminal Theme Support

extension ClaudeTerminalView {

    /// Apply a terminal theme
    /// - Parameter theme: Theme to apply
    func applyTheme(_ theme: TerminalTheme) {
        nativeBackgroundColor = theme.background
        nativeForegroundColor = theme.foreground
        caretColor = theme.cursor

        // Install ANSI color palette
        let ansiColors: [Color] = [
            Color(theme.black),
            Color(theme.red),
            Color(theme.green),
            Color(theme.yellow),
            Color(theme.blue),
            Color(theme.magenta),
            Color(theme.cyan),
            Color(theme.white),
            Color(theme.brightBlack),
            Color(theme.brightRed),
            Color(theme.brightGreen),
            Color(theme.brightYellow),
            Color(theme.brightBlue),
            Color(theme.brightMagenta),
            Color(theme.brightCyan),
            Color(theme.brightWhite)
        ]

        installColors(ansiColors)
    }
}

// MARK: - Terminal Theme Definition

struct TerminalTheme {
    let name: String
    let background: NSColor
    let foreground: NSColor
    let cursor: NSColor

    // ANSI base colors
    let black: NSColor
    let red: NSColor
    let green: NSColor
    let yellow: NSColor
    let blue: NSColor
    let magenta: NSColor
    let cyan: NSColor
    let white: NSColor

    // ANSI bright colors
    let brightBlack: NSColor
    let brightRed: NSColor
    let brightGreen: NSColor
    let brightYellow: NSColor
    let brightBlue: NSColor
    let brightMagenta: NSColor
    let brightCyan: NSColor
    let brightWhite: NSColor

    // MARK: - Preset Themes

    /// VS Code Dark theme (default)
    static let vscode = TerminalTheme(
        name: "VS Code Dark",
        background: NSColor(hex: "#1E1E1E")!,
        foreground: NSColor(hex: "#CCCCCC")!,
        cursor: NSColor(hex: "#AEAFAD")!,
        black: NSColor(hex: "#000000")!,
        red: NSColor(hex: "#CD3131")!,
        green: NSColor(hex: "#0DBC79")!,
        yellow: NSColor(hex: "#E5E510")!,
        blue: NSColor(hex: "#2472C8")!,
        magenta: NSColor(hex: "#BC3FBC")!,
        cyan: NSColor(hex: "#11A8CD")!,
        white: NSColor(hex: "#E5E5E5")!,
        brightBlack: NSColor(hex: "#666666")!,
        brightRed: NSColor(hex: "#F14C4C")!,
        brightGreen: NSColor(hex: "#23D18B")!,
        brightYellow: NSColor(hex: "#F5F543")!,
        brightBlue: NSColor(hex: "#3B8EEA")!,
        brightMagenta: NSColor(hex: "#D670D6")!,
        brightCyan: NSColor(hex: "#29B8DB")!,
        brightWhite: NSColor(hex: "#FFFFFF")!
    )

    /// Dracula theme
    static let dracula = TerminalTheme(
        name: "Dracula",
        background: NSColor(hex: "#282A36")!,
        foreground: NSColor(hex: "#F8F8F2")!,
        cursor: NSColor(hex: "#F8F8F2")!,
        black: NSColor(hex: "#21222C")!,
        red: NSColor(hex: "#FF5555")!,
        green: NSColor(hex: "#50FA7B")!,
        yellow: NSColor(hex: "#F1FA8C")!,
        blue: NSColor(hex: "#BD93F9")!,
        magenta: NSColor(hex: "#FF79C6")!,
        cyan: NSColor(hex: "#8BE9FD")!,
        white: NSColor(hex: "#F8F8F2")!,
        brightBlack: NSColor(hex: "#6272A4")!,
        brightRed: NSColor(hex: "#FF6E6E")!,
        brightGreen: NSColor(hex: "#69FF94")!,
        brightYellow: NSColor(hex: "#FFFFA5")!,
        brightBlue: NSColor(hex: "#D6ACFF")!,
        brightMagenta: NSColor(hex: "#FF92DF")!,
        brightCyan: NSColor(hex: "#A4FFFF")!,
        brightWhite: NSColor(hex: "#FFFFFF")!
    )

    /// One Dark theme
    static let oneDark = TerminalTheme(
        name: "One Dark",
        background: NSColor(hex: "#282C34")!,
        foreground: NSColor(hex: "#ABB2BF")!,
        cursor: NSColor(hex: "#528BFF")!,
        black: NSColor(hex: "#282C34")!,
        red: NSColor(hex: "#E06C75")!,
        green: NSColor(hex: "#98C379")!,
        yellow: NSColor(hex: "#E5C07B")!,
        blue: NSColor(hex: "#61AFEF")!,
        magenta: NSColor(hex: "#C678DD")!,
        cyan: NSColor(hex: "#56B6C2")!,
        white: NSColor(hex: "#ABB2BF")!,
        brightBlack: NSColor(hex: "#5C6370")!,
        brightRed: NSColor(hex: "#E06C75")!,
        brightGreen: NSColor(hex: "#98C379")!,
        brightYellow: NSColor(hex: "#E5C07B")!,
        brightBlue: NSColor(hex: "#61AFEF")!,
        brightMagenta: NSColor(hex: "#C678DD")!,
        brightCyan: NSColor(hex: "#56B6C2")!,
        brightWhite: NSColor(hex: "#FFFFFF")!
    )
}
