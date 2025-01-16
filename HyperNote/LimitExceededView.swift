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

            Text("Daily Limit Reached")
                .font(.headline)

            Text("You've reached the daily limit of 25 quick wake-ups.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button("Upgrade to Hyper+") {
                // Handle upgrade action
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
        }
        .padding()
        .frame(width: 300)
    }
}

class LimitExceededWindowController: NSWindowController {
    private let defaultWidth: CGFloat = 300
    private let defaultHeight: CGFloat = 200

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: defaultWidth, height: defaultHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Daily Limit Reached"
        window.center()
        window.isReleasedWhenClosed = false

        let hostingController = NSHostingController(rootView: LimitExceededView())
        window.contentViewController = hostingController

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
