//
//  LimitExceededView.swift
//  HyperNote
//
//  Created by LC John on 1/16/25.
//

import Foundation
import SwiftUI

struct LimitExceededView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.yellow)

            Text("Limit Reached")
                .font(.headline)

            Text(
                "Reached daily limit of \(AppConfig.QuickWakeup.dailyLimit) shortcut wake-ups."
            )
            .multilineTextAlignment(.center)
            .foregroundColor(.secondary)

            Text(
                "You can still launch normally from dock."
            )
            .multilineTextAlignment(.center)
            .foregroundColor(.secondary)

            Button("Unlimited on Hyper+") {
                // Handle upgrade action
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
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

        // Center the window vertically and horizontally on the screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = window.frame
            let newOriginX = screenFrame.midX - windowFrame.width / 2
            let newOriginY = screenFrame.midY - windowFrame.height / 2
            window.setFrameOrigin(NSPoint(x: newOriginX, y: newOriginY))
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
