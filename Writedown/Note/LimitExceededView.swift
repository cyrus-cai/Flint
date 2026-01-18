//
//  LimitExceededView.swift
//  Writedown
//
//  Created by LC John on 1/16/25.
//

import Foundation
import SwiftUI

struct LimitExceededView: View {
    @AppStorage("userEmail") private var userEmail: String = ""
    @StateObject private var paymentVM = PaymentViewModel()

    var body: some View {
        VStack(spacing: 24) {
            // Header with icon and gradient background
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text(L("Daily Limit Reached"))
                    .font(.system(size: 20, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)

            // Message content
            VStack(spacing: 12) {
                Text(
                    String(format: L("You've reached the daily limit of %d quick wake-ups."), AppConfig.QuickWakeup.dailyLimit)
                )
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

                Text(L("You can still launch Writedown from the dock."))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            // Action buttons
            VStack(spacing: 12) {
                // 升级按钮
                Button(action: {
                    Task {
                        await paymentVM.startPayment()
                    }
                }) {
                    HStack(spacing: 8) {
                        if paymentVM.isProcessing {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 16, height: 16)
                        }
                        Text(paymentVM.isProcessing ? L("Processing...") : L("RMB 48 Lifetime-Pro"))
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(
                        LinearGradient(
                            colors: [Color(.systemPurple), Color(.systemPink)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(8)
                    .shadow(color: Color(.systemPurple).opacity(0.3), radius: 8)
                }
                .buttonStyle(.plain)
                .disabled(paymentVM.isProcessing)

                // 恢复购买按钮
                Button(action: {
                    Task {
                        await paymentVM.restorePurchase()
                    }
                }) {
                    HStack(spacing: 6) {
                        if paymentVM.isProcessing {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 14, height: 14)
                        }
                        Text(L("Restore Purchase"))
                            .font(.system(size: 13))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(paymentVM.isProcessing)

                // 登录按钮（仅未登录时显示）
                if userEmail.isEmpty {
                    Button(action: {
                        if let url = URL(string: "https://www.writedown.space/login") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Text(L("Already subscribed? Log in"))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .padding(20)
        .frame(width: 360)
        .background(Color.clear)
        .alert(
            L("Error"),
            isPresented: Binding(
                get: { paymentVM.error != nil },
                set: { if !$0 { paymentVM.clearError() } }
            ),
            presenting: paymentVM.error
        ) { error in
            Button(L("Retry")) {
                Task { await paymentVM.retry() }
            }
            Button(L("Cancel"), role: .cancel) {
                paymentVM.clearError()
            }
        } message: { error in
            VStack {
                Text(error.localizedDescription)
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.caption)
                }
            }
        }
        .alert(L("Success"), isPresented: $paymentVM.showSuccessAlert) {
            Button(L("OK")) {
                // 关闭窗口
                NSApp.keyWindow?.close()
            }
        } message: {
            Text(L("Welcome to Writedown Pro! You now have unlimited quick wake-ups."))
        }
    }
}

class LimitExceededWindowController: NSWindowController {
    private let defaultWidth: CGFloat = 300
    private let defaultHeight: CGFloat = 280

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: defaultWidth, height: defaultHeight),
            styleMask: [
                .titled,
                .closable,
                .fullSizeContentView,
            ],
            backing: .buffered,
            defer: false
        )

        window.title = L("Daily Limit Reached")
        window.isReleasedWhenClosed = false
        window.level = .floating

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        
        // macOS 26+ Liquid Glass 适配
        if #available(macOS 26.0, *) {
            // macOS 26+: 系统自动处理 Liquid Glass 效果
            window.isOpaque = false
            // 不设置 backgroundColor，让玻璃效果自然显示
        } else {
            // macOS 15-25: 使用传统窗口背景
            window.backgroundColor = NSColor.windowBackgroundColor
        }

        let hostingController = NSHostingController(rootView: LimitExceededView())
        window.contentViewController = hostingController

        // macOS 26+ Liquid Glass 适配: 仅在旧系统添加 NSVisualEffectView
        if #available(macOS 26.0, *) {
            // macOS 26+: 不需要手动添加毛玻璃效果
        } else {
            // macOS 15-25: 添加传统毛玻璃效果
            let visualEffectView = NSVisualEffectView()
            visualEffectView.material = .sidebar
            visualEffectView.state = .active
            visualEffectView.blendingMode = .behindWindow

            if let contentView = window.contentView {
                visualEffectView.frame = contentView.bounds
                contentView.addSubview(visualEffectView, positioned: .below, relativeTo: nil)

                visualEffectView.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    visualEffectView.topAnchor.constraint(equalTo: contentView.topAnchor),
                    visualEffectView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                    visualEffectView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                    visualEffectView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                ])
            }
        }

        super.init(window: window)

        // Center the window both horizontally and vertically on the screen
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let windowFrame = window.frame

            // Calculate center position
            let centerX = screenFrame.midX
            let centerY = screenFrame.midY

            // Calculate window origin to achieve center position
            let windowX = centerX - (windowFrame.width / 2) - 180
            let windowY = centerY - (windowFrame.height / 2)

            window.setFrameOrigin(NSPoint(x: windowX, y: windowY))
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
