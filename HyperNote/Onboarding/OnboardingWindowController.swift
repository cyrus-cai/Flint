//
//  OnboardingWindowController.swift
//  HyperNote
//
//  Created by LC John on 1/17/25.
//

import Foundation
import SwiftUI

class OnboardingWindowController: NSWindowController {
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)

        window.title = "Welcome to HyperNote"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor.windowBackgroundColor

        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .sidebar
        visualEffectView.state = .active
        visualEffectView.blendingMode = .behindWindow

        let isFirstLaunch = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        let hostingController = NSHostingController(
            rootView: OnboardingView(
                isFirstLaunch: .init(
                    get: { !isFirstLaunch },
                    set: { newValue in
                        UserDefaults.standard.set(!newValue, forKey: "hasCompletedOnboarding")
                    }
                )
            )
        )
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

        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let windowFrame = window.frame

            let centerX = screenFrame.midX
            let centerY = screenFrame.midY

            let windowX = centerX - (windowFrame.width / 2) - 240
            let windowY = centerY - (windowFrame.height / 2) - 200

            window.setFrameOrigin(NSPoint(x: windowX, y: windowY))
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
