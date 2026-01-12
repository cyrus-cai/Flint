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
                // .shadow(color: .yellow.opacity(0.3), radius: 8)

                Text("Daily Limit Reached")
                    .font(.system(size: 20, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)

            // Message content
            VStack(spacing: 12) {
                Text(
                    "You've reached the daily limit of \(AppConfig.QuickWakeup.dailyLimit) quick wake-ups."
                )
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

                Text("You can still launch Writedown from the dock.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            // Action buttons
            VStack(spacing: 12) {
                Button(action: {
                    Task {
                        do {
                            let request = StripeCheckout.CheckoutRequest(
                                planId: "pro",
                                email: UserDefaults.standard.string(forKey: "userEmail"),
                                deviceId: DeviceManager.shared.getDeviceIdentifier()
                            )

                            let response = await StripeCheckout.createCheckoutSession(
                                request: request,
                                origin: "https://www.writedown.space/stripePayment"
                            )

                            if let urlString = response.url,
                                let url = URL(string: urlString)
                            {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }) {
                    Text("RMB 48 Lifetime-Pro")
                        .font(.system(size: 14, weight: .medium))
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

                if userEmail.isEmpty {
                    Button(action: {
                        if let url = URL(string: "https://www.writedown.space/login") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Text("Already subscribed? Log in")
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

        window.title = "Daily Limit Reached"
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
