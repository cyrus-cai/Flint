//
//  LimitExceededView.swift
//  HyperNote
//
//  Created by LC John on 1/16/25.
//

import Foundation
import SwiftUI

struct LimitExceededView: View {
    @AppStorage("userEmail") private var userEmail: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.yellow)

            Text("Daily Limit Reached")
                .font(.headline)

            Text(
                "You've reached the daily limit of \(AppConfig.QuickWakeup.dailyLimit) quick wake-ups."
            )
            .multilineTextAlignment(.center)
            .foregroundColor(.secondary)

            Text("You can still launch HyperNote from the dock.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            // Main upgrade button
            Button(action: {
                Task {
                    do {
                        let request = StripeCheckout.CheckoutRequest(
                            planId: "pro",
                            email: UserDefaults.standard.string(forKey: "userEmail")
                        )

                        let response = await StripeCheckout.createCheckoutSession(
                            request: request,
                            origin: "https://www.writedown.space/stripePayment"
                        )

                        if let urlString = response.url,
                            let url = URL(string: urlString)
                        {
                            NSWorkspace.shared.open(url)
                        } else if let error = response.error {
                            print("Payment Error: \(error.message)")
                        }
                    }
                }
            }) {
                Text("Upgrade to Pro")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        LinearGradient(
                            colors: [Color(.systemPurple), Color(.systemPink)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)

            // Login button for existing subscribers
            if userEmail.isEmpty {
                Button(action: {
                    if let url = URL(string: "https://www.writedown.space/login") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Text("Subscribed? Log in")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(width: 360)
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
        window.backgroundColor = NSColor.windowBackgroundColor

        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .sidebar
        visualEffectView.state = .active
        visualEffectView.blendingMode = .behindWindow

        let hostingController = NSHostingController(rootView: LimitExceededView())
        window.contentViewController = hostingController

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
