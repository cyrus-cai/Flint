import AppKit
import Foundation
import SwiftUI

class WindowManager {
    static let shared = WindowManager()
    private(set) var activeWindow: MainWindowController?
    private var windows: [MainWindowController] = []
    private var limitExceededWindow: LimitExceededWindowController?

    func createNewWindow() {
        // For backwards compatibility, redirect to new method
        createOrShowMainWindow()
    }

    func createOrShowMainWindow() {
        if let window = activeWindow {
            window.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            let windowController = MainWindowController()
            windows.append(windowController)
            activeWindow = windowController
            windowController.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func createSettingsWindow() {
        SettingsWindowController.shared.showWindow(nil)
    }

    func closeWindow(_ windowController: MainWindowController) {
        if let index = windows.firstIndex(where: { $0 === windowController }) {
            windows.remove(at: index)
        }
        if activeWindow === windowController {
            activeWindow = windows.last
        }
    }

    func showOnboardingIfNeeded() {

        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        print(hasCompletedOnboarding)  // 打印出布尔值

        if !hasCompletedOnboarding {
            let onboardingController = OnboardingWindowController()
            onboardingController.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func createLimitExceededWindow() {
        if limitExceededWindow == nil {
            let window = LimitExceededWindowController()
            window.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            limitExceededWindow = window

            // Add window close observer
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(limitExceededWindowDidClose),
                name: NSWindow.willCloseNotification,
                object: window.window
            )
        }
    }

    @objc private func limitExceededWindowDidClose(_ notification: Notification) {
        limitExceededWindow = nil
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.willCloseNotification,
            object: notification.object
        )
    }
}

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = NSColor.clear

        super.init(window: window)

        window.center()
        window.title = "Settings"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentView = NSHostingView(rootView: SettingsView())

        // 应用当前的外观设置
        if let appearanceMode = AppearanceMode(
            rawValue: UserDefaults.standard.string(forKey: "appearanceMode") ?? "System")
        {
            switch appearanceMode {
            case .system:
                window.appearance = nil
            case .light:
                window.appearance = NSAppearance(named: .aqua)
            case .dark:
                window.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class MainWindowController: NSWindowController {
    private let defaultWidth: CGFloat = 425
    private let defaultHeight: CGFloat = 120
    private let minHeight: CGFloat = 120
    private var maxHeight: CGFloat {
        return (NSScreen.main?.frame.height ?? 720) * 0.75
    }

    private var trackingArea: NSTrackingArea?
    private var isResizing: Bool = false

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: defaultWidth, height: defaultHeight),
            styleMask: [
                .titled,
                .closable,
                .fullSizeContentView,
                .resizable,
            ],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)

        configureWindow()
        setupContentView()
        setupInitialPosition()

        DispatchQueue.main.async { [weak self] in
            self?.setupTrackingArea()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureWindow() {
        guard let window = window else { return }

        window.title = "Hyper Note"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .clear
        window.hasShadow = true
        window.invalidateShadow()

        window.level = .floating
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .transient,
        ]

        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.isMovableByWindowBackground = true
        window.isOpaque = false

        window.minSize = NSSize(width: defaultWidth, height: minHeight)
        window.maxSize = NSSize(width: defaultWidth, height: maxHeight)

        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .popover
        visualEffectView.state = .active
        visualEffectView.blendingMode = .withinWindow

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

        window.backgroundColor = NSColor.windowBackgroundColor
        //        window.backgroundColor = NSColor.windowBackgroundColor

        configureWindowButtons()
        setupResizeNotifications()
    }

    private func configureWindowButtons() {
        guard let window = window,
            let closeButton = window.standardWindowButton(.closeButton),
            let minimizeButton = window.standardWindowButton(.miniaturizeButton),
            let zoomButton = window.standardWindowButton(.zoomButton)
        else { return }

        minimizeButton.isHidden = true
        zoomButton.isHidden = true

        // 创建自定义按钮
        let customCloseButton = NSButton(frame: closeButton.frame)
        customCloseButton.bezelStyle = .regularSquare
        customCloseButton.isBordered = false
        customCloseButton.title = ""
        customCloseButton.image = NSImage(
            systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)
        customCloseButton.contentTintColor = .systemGray
        customCloseButton.alphaValue = 0  // 默认完全隐藏
        customCloseButton.target = window
        customCloseButton.action = #selector(NSWindow.close)

        // 替换原始按钮
        closeButton.superview?.addSubview(customCloseButton)
        closeButton.isHidden = true
    }

    private func setupResizeNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillResize),
            name: NSWindow.willStartLiveResizeNotification,
            object: window
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidEndResize),
            name: NSWindow.didEndLiveResizeNotification,
            object: window
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResize),
            name: NSWindow.didResizeNotification,
            object: window
        )
    }

    private func setupTrackingArea() {
        guard let contentView = window?.contentView else { return }

        if let existingTrackingArea = trackingArea {
            contentView.removeTrackingArea(existingTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: contentView.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )

        contentView.addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if let userInfo = event.trackingArea?.userInfo as? [String: NSButton],
            let button = userInfo["button"]
        {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                button.animator().alphaValue = 0.8
            }
        } else {
            setButtonsAlpha(1.0)
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if let userInfo = event.trackingArea?.userInfo as? [String: NSButton],
            let button = userInfo["button"]
        {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                button.animator().alphaValue = 0.5
            }
        } else {
            setButtonsAlpha(0)
        }
    }

    private func setButtonsAlpha(_ alpha: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            if let closeButton = window?.standardWindowButton(.closeButton)?.superview?.subviews
                .last as? NSButton
            {
                closeButton.animator().alphaValue = alpha == 0 ? 0 : 0.8  // 悬停时显示，非悬停时完全隐藏
            }
        }
    }

    private var heightObserver: NSKeyValueObservation?

    private func setupContentView() {
        let contentView = ContentView()
            .onPreferenceChange(ContentHeightPreferenceKey.self) { [weak self] height in
                print("changed")
                self?.updateWindowHeight(height)
            }

        let hostingController = NSHostingController(rootView: contentView)
        window?.contentViewController = hostingController

        // Observe content view frame changes
        heightObserver = hostingController.view.observe(\.frame) { [weak self] view, _ in
            let contentHeight = view.frame.height
            self?.updateWindowHeight(contentHeight)
        }
    }

    private func updateWindowHeight(_ contentHeight: CGFloat) {
        guard !isResizing, let window = window else { return }

        window.minSize = NSSize(width: defaultWidth, height: minHeight)
        window.maxSize = NSSize(width: defaultWidth, height: maxHeight)

        let newHeight = min(max(contentHeight, minHeight), maxHeight)
        var frame = window.frame
        frame.origin.y += frame.height - newHeight
        frame.size.height = newHeight

        print(frame.size.height, "height")

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.0
            window.animator().setFrame(frame, display: true)
        }
    }

    @objc private func contentViewFrameDidChange(_ notification: Notification) {
        setupTrackingArea()
    }

    private func setupInitialPosition() {
        guard let window = window else { return }

        if let savedSize = loadSavedSize() {
            var frame = window.frame
            frame.size = savedSize
            window.setFrame(frame, display: true)
        }

        if let savedPosition = getSavedPosition() {
            window.setFrameTopLeftPoint(savedPosition)
        } else {
            setDefaultPosition()
        }
    }

    private func setDefaultPosition() {
        guard let window = window, let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let rightTopX = screenFrame.maxX - defaultWidth - 20
        let rightTopY = screenFrame.maxY - 20

        window.setFrameTopLeftPoint(NSPoint(x: rightTopX, y: rightTopY))
    }

    func toggleWindow() {
        guard let window = window else { return }

        if window.isVisible {
            hideWindow()
        } else {
            showWindow(nil)
        }
    }

    override func showWindow(_ sender: Any?) {
        guard let window = self.window else {
            super.showWindow(sender)
            return
        }

        // 先将透明度设为 0，这样窗口初始状态为透明，
        // 注意这里不改变窗口的位置，保持原有 frame
        window.alphaValue = 0.0

        // 调用 super.showWindow 展示窗口（位置不变）
        super.showWindow(sender)

        // 使用 NSAnimationContext 进行淡入动画，将透明度由 0 渐变到 1
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2  // 可根据需要调整时长
            window.animator().alphaValue = 1.0
        }, completionHandler: nil)
    }

    private func hideWindow() {
        window?.orderOut(nil)
    }

    private func isPositionVisible(_ position: NSPoint) -> Bool {
        return NSScreen.screens.contains { screen in
            screen.frame.contains(position)
        }
    }

    // MARK: - Size Management
    @objc private func windowWillResize(_ notification: Notification) {
        isResizing = true
    }

    @objc private func windowDidEndResize(_ notification: Notification) {
        isResizing = false
        saveWindowSize()
    }

    @objc private func windowDidResize(_ notification: Notification) {
        guard let window = window else { return }

        var frame = window.frame

        // Constrain width to defaultWidth
        frame.size.width = defaultWidth

        // Constrain height between minHeight and maxHeight
        frame.size.height = min(max(frame.size.height, minHeight), maxHeight)

        // Apply the constrained frame if it differs from current
        if frame != window.frame {
            window.setFrame(frame, display: true)
        }
    }

    private func saveWindowSize() {
        guard let window = window else { return }
        let size = window.frame.size
        UserDefaults.standard.set(
            ["width": size.width, "height": size.height], forKey: "WindowSize")
    }

    private func loadSavedSize() -> NSSize? {
        guard
            let sizeData = UserDefaults.standard.object(forKey: "WindowSize") as? [String: CGFloat],
            let width = sizeData["width"],
            let height = sizeData["height"]
        else {
            return nil
        }
        return NSSize(width: width, height: height)
    }

    // MARK: - Position Management
    private func getSavedPosition() -> NSPoint? {
        let defaults = UserDefaults.standard
        guard let positionData = defaults.object(forKey: "WindowPosition") as? [String: CGFloat],
            let x = positionData["x"],
            let y = positionData["y"]
        else {
            return nil
        }
        return NSPoint(x: x, y: y)
    }

    private func savePosition() {
        guard let position = window?.frame.origin else { return }
        let positionData: [String: CGFloat] = [
            "x": position.x,
            "y": position.y,
        ]
        UserDefaults.standard.set(positionData, forKey: "WindowPosition")
    }

    @objc private func windowDidMove(_ notification: Notification) {
        savePosition()
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        window?.level = .floating
    }

    deinit {
        if let trackingArea = trackingArea,
            let contentView = window?.contentView
        {
            contentView.removeTrackingArea(trackingArea)
        }
        NotificationCenter.default.removeObserver(self)
        WindowManager.shared.closeWindow(self)
    }
}
