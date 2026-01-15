//
//  OnboardingWindowController.swift
//  Writedown
//
//  Created by LC John on 1/17/25.
//

import Cocoa
import SwiftUI

class OnboardingWindowController: NSWindowController {
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = L("Welcome to Writedown")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true

        // 设置内容视图
        let contentView = NSHostingView(
            rootView: OnboardingView(isFirstLaunch: .constant(true))
        )
        window.contentView = contentView

        // macOS 26+ Liquid Glass 适配
        if #available(macOS 26.0, *) {
            // macOS 26+: 系统自动处理 Liquid Glass 效果
            // 不需要手动添加 NSVisualEffectView
            window.isOpaque = false
        } else {
            // macOS 15-25: 添加传统毛玻璃效果
            if let contentView = window.contentView {
                let visualEffectView = NSVisualEffectView()
                visualEffectView.material = .windowBackground
                visualEffectView.state = .active
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

        // 隐藏标准窗口按钮（红绿灯）
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        // 设置窗口位置
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let windowFrame = window.frame

            let centerX = screenFrame.midX
            let centerY = screenFrame.midY

            let windowX = centerX - (windowFrame.width / 2)
            let windowY = centerY - (windowFrame.height / 2)

            window.setFrameOrigin(NSPoint(x: windowX, y: windowY))
        }

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
