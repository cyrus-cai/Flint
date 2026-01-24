//
//  ClaudeCodeOutputView.swift
//  Writedown
//
//  Created by AI Agent on 1/23/26.
//

import SwiftUI

/// View for displaying Claude Code CLI output in real-time
struct ClaudeCodeOutputView: View {
    @ObservedObject var service = ClaudeCodeService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showCopiedToast = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerBar

            Divider()

            // Output Area
            outputArea

            Divider()

            // Footer
            footerBar
        }
        .frame(width: 700, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            Image(systemName: "terminal")
                .font(.system(size: 16))
                .foregroundColor(.secondary)

            Text("Claude Code")
                .font(.headline)

            Spacer()

            // State indicator
            stateIndicator

            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - State Indicator

    @ViewBuilder
    private var stateIndicator: some View {
        switch service.state {
        case .idle:
            EmptyView()

        case .preparing:
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
                Text("Preparing...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

        case .running:
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("Running")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

        case .waitingForPermission:
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .foregroundColor(.yellow)
                    .font(.system(size: 12))
                Text("Waiting for approval")
                    .font(.caption)
                    .foregroundColor(.yellow)
            }

        case .completed:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 12))
                Text("Completed")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

        case .failed(let reason):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 12))
                Text("Failed: \(reason)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Output Area

    private var outputArea: some View {
        VStack(spacing: 0) {
            // Permission request banner
            if let permission = service.pendingPermission {
                permissionBanner(for: permission)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if service.outputLines.isEmpty {
                            emptyStateView
                        } else {
                            ForEach(service.outputLines) { line in
                                OutputLineView(line: line)
                                    .id(line.id)
                            }
                        }
                    }
                    .padding(12)
                }
                .background(Color(NSColor.textBackgroundColor))
                .onChange(of: service.outputLines.count) { _ in
                    if let last = service.outputLines.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Permission Banner

    private func permissionBanner(for request: ClaudeCodeService.PermissionRequest) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .foregroundColor(.yellow)
                .font(.system(size: 20))

            VStack(alignment: .leading, spacing: 4) {
                Text("Permission Required")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)

                Text(request.displayDescription)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            Spacer()

            // Deny button
            Button {
                service.respondToPermission(allow: false, message: "User denied")
            } label: {
                Text("Deny")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)

            // Allow button
            Button {
                service.respondToPermission(allow: true)
            } label: {
                Text("Allow")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.yellow.opacity(0.15))
        .overlay(
            Rectangle()
                .fill(Color.yellow)
                .frame(width: 4),
            alignment: .leading
        )
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No output yet")
                .font(.title3)
                .foregroundColor(.secondary)

            Text("Output from Claude Code will appear here")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Footer Bar

    private var footerBar: some View {
        HStack {
            // Line count
            Text("\(service.outputLines.count) lines")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            // Control buttons
            HStack(spacing: 8) {
                // Copy button
                Button {
                    copyAllOutput()
                } label: {
                    Label("Copy All", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(service.outputLines.isEmpty)
                .help("Copy all output to clipboard")

                // Clear button
                Button {
                    service.clearOutput()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(service.outputLines.isEmpty || service.state == .running)
                .help("Clear output")

                // Cancel button
                if service.state == .running {
                    Button {
                        service.cancel()
                    } label: {
                        Label("Cancel", systemImage: "stop.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .help("Cancel execution")
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            Group {
                if showCopiedToast {
                    toastView
                }
            }
        )
    }

    private var toastView: some View {
        Text("Copied to clipboard")
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(6)
            .transition(.opacity)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation {
                        showCopiedToast = false
                    }
                }
            }
    }

    // MARK: - Actions

    private func copyAllOutput() {
        let fullOutput = service.outputLines
            .map { $0.content }
            .joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullOutput, forType: .string)

        withAnimation {
            showCopiedToast = true
        }
    }
}

// MARK: - Output Line View

struct OutputLineView: View {
    let line: ClaudeCodeService.OutputLine

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(timeFormatter.string(from: line.timestamp))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.7))
                .frame(width: 60, alignment: .trailing)

            // Type indicator
            typeIndicator
                .frame(width: 16)

            // Content
            Text(line.content)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(colorForType(line.type))
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(backgroundForType(line.type))
        .cornerRadius(4)
    }

    @ViewBuilder
    private var typeIndicator: some View {
        switch line.type {
        case .stdout:
            Circle()
                .fill(Color.blue.opacity(0.6))
                .frame(width: 6, height: 6)

        case .stderr:
            Circle()
                .fill(Color.orange.opacity(0.6))
                .frame(width: 6, height: 6)

        case .system:
            Image(systemName: "info.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(.purple.opacity(0.7))

        case .thinking:
            Image(systemName: "brain")
                .font(.system(size: 10))
                .foregroundColor(.cyan.opacity(0.8))

        case .toolUse:
            Image(systemName: "wrench.fill")
                .font(.system(size: 10))
                .foregroundColor(.orange.opacity(0.8))

        case .toolResult:
            Image(systemName: "doc.text.fill")
                .font(.system(size: 10))
                .foregroundColor(.green.opacity(0.8))

        case .assistant:
            Image(systemName: "bubble.left.fill")
                .font(.system(size: 10))
                .foregroundColor(.blue.opacity(0.8))

        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundColor(.red.opacity(0.8))
        }
    }

    private func colorForType(_ type: ClaudeCodeService.StreamType) -> Color {
        switch type {
        case .stdout:
            return Color.primary
        case .stderr:
            return Color.orange
        case .system:
            return Color.purple
        case .thinking:
            return Color.cyan.opacity(0.9)
        case .toolUse:
            return Color.orange
        case .toolResult:
            return Color.green.opacity(0.9)
        case .assistant:
            return Color.primary
        case .error:
            return Color.red
        }
    }

    private func backgroundForType(_ type: ClaudeCodeService.StreamType) -> Color {
        switch type {
        case .thinking:
            return Color.cyan.opacity(0.05)
        case .toolUse:
            return Color.orange.opacity(0.05)
        case .toolResult:
            return Color.green.opacity(0.05)
        case .error:
            return Color.red.opacity(0.08)
        default:
            return Color.clear
        }
    }
}

// MARK: - Previews

#Preview {
    ClaudeCodeOutputView()
}
