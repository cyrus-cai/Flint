import AppKit
import Foundation
import KeyboardShortcuts
import SwiftUI

class WindowManager {
    static let shared = WindowManager()
    private(set) var activeWindow: MainWindowController?
    private var windows: [MainWindowController] = []
    private var onboardingWindowController: OnboardingWindowController?

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

        if !hasCompletedOnboarding {
            showOnboarding()
        }
    }

    func replayOnboarding() {
        KeyboardShortcuts.setShortcut(nil, for: .quickWakeup)
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        dismissOnboarding()
        showOnboarding()
    }

    func dismissOnboarding() {
        onboardingWindowController?.close()
        onboardingWindowController = nil
    }

    private func showOnboarding() {
        if onboardingWindowController == nil {
            onboardingWindowController = OnboardingWindowController()
        }

        onboardingWindowController?.showWindow(nil)
        onboardingWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        
        // macOS 26+ Liquid Glass 适配
        if #available(macOS 26.0, *) {
            // macOS 26+: 系统自动处理玻璃效果
            // 不设置 backgroundColor，让 Liquid Glass 自然显示
        } else {
            // macOS 15-25: 可选择设置透明背景
            // window.backgroundColor = NSColor.clear
        }

        super.init(window: window)

        window.center()
        window.titleVisibility = .hidden
        window.title = ""
        window.titlebarAppearsTransparent = true
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
    private weak var trackingAreaView: NSView?
    private var isResizing: Bool = false
    /// When true, window height changes are suppressed. Used during note loading
    /// so the window stays stable while SwiftUI fills in the new content.
    private(set) var isHeightFrozen: Bool = false
    private var lastOptionKeyTapDate: Date?
    private var optionKeyTapCount: Int = 0  // 用于记录 Option 键点击次数
    private var optionKeyTapMonitor: Any?
    private var globalOptionKeyTapMonitor: Any?
    private lazy var contentHostingView: NSHostingView<AnyView> = {
        let rootView = AnyView(
            ContentView()
                .onPreferenceChange(ContentHeightPreferenceKey.self) { [weak self] height in
                    self?.updateWindowHeight(height)
                }
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        return hostingView
    }()
    private var heightObserver: NSKeyValueObservation?

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

        DispatchQueue.main.async { [weak self] in
            self?.setupTrackingArea()
        }

        configureWindow()
        setupContentView()
        setupInitialPosition()
        setupOptionKeyMonitor()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTransparencyChange),
            name: .windowTransparencyDidChange,
            object: nil
        )
    }

    // ... (existing code)

    private func checkTripleOptionKey(_ event: NSEvent) {
        let onlyOptionPressed = event.modifierFlags.contains(.option) &&
            !event.modifierFlags.contains(.command) &&
            !event.modifierFlags.contains(.control) &&
            !event.modifierFlags.contains(.shift) &&
            !event.modifierFlags.contains(.function)

        if onlyOptionPressed {
            let now = Date()
            
            if let lastDate = self.lastOptionKeyTapDate, now.timeIntervalSince(lastDate) < 0.3 {
                optionKeyTapCount += 1
            } else {
                optionKeyTapCount = 1
            }
            
            self.lastOptionKeyTapDate = now
            
            if optionKeyTapCount >= 3 {
                WindowManager.shared.createOrShowMainWindow()
                NotificationCenter.default.post(
                    name: Notification.Name("ShowRecentNotesNotification"),
                    object: nil
                )
                
                optionKeyTapCount = 0
                self.lastOptionKeyTapDate = nil
                return
            }
            
            if optionKeyTapCount == 2 && UserDefaults.standard.bool(forKey: "enableDoubleOption") {
                self.performQuickWakeup()
            }
            
        } else if event.modifierFlags.isEmpty {
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureWindow() {
        guard let window = window else { return }

        window.title = "Flint"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        applyTransparency()

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

        window.minSize = NSSize(width: defaultWidth, height: minHeight)
        window.maxSize = NSSize(width: defaultWidth, height: maxHeight)

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

    private func applyTransparency() {
        guard let window = window else { return }
        let isTransparent = UserDefaults.standard.object(forKey: AppStorageKeys.windowTransparent) as? Bool ?? AppDefaults.windowTransparent

        if isTransparent {
            window.isOpaque = false
            window.backgroundColor = .clear
        } else {
            window.isOpaque = true
            window.backgroundColor = .noteWindowBackgroundColor
        }
        window.invalidateShadow()
    }

    @objc private func handleTransparencyChange() {
        applyTransparency()
        setupContentView()
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

        clearTrackingArea()

        let trackingArea = NSTrackingArea(
            rect: contentView.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )

        contentView.addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
        trackingAreaView = contentView
    }

    private func clearTrackingArea() {
        guard let existingTrackingArea = trackingArea else { return }
        trackingAreaView?.removeTrackingArea(existingTrackingArea)
        trackingArea = nil
        trackingAreaView = nil
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

    private func setupContentView() {
        let hostingView = contentHostingView
        hostingView.wantsLayer = true

        let isTransparent = UserDefaults.standard.object(forKey: AppStorageKeys.windowTransparent) as? Bool ?? AppDefaults.windowTransparent
        hostingView.removeFromSuperview()
        clearTrackingArea()

        if isTransparent {
            if #available(macOS 26.0, *) {
                hostingView.layer?.cornerRadius = DesignSystem.standardCornerRadius
                hostingView.layer?.masksToBounds = true

                let containerView = NSView()
                containerView.wantsLayer = true
                containerView.layer?.cornerRadius = DesignSystem.standardCornerRadius
                containerView.layer?.masksToBounds = true

                let visualEffectView = NSVisualEffectView()
                visualEffectView.material = .hudWindow
                visualEffectView.blendingMode = .behindWindow
                visualEffectView.state = .active
                visualEffectView.wantsLayer = true

                containerView.addSubview(visualEffectView)
                containerView.addSubview(hostingView)

                visualEffectView.translatesAutoresizingMaskIntoConstraints = false
                hostingView.translatesAutoresizingMaskIntoConstraints = false

                NSLayoutConstraint.activate([
                    visualEffectView.topAnchor.constraint(equalTo: containerView.topAnchor),
                    visualEffectView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                    visualEffectView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                    visualEffectView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

                    hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
                    hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                    hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                    hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
                ])

                window?.contentView = containerView
            } else {
                hostingView.layer?.cornerRadius = 12
                hostingView.layer?.masksToBounds = true
                hostingView.translatesAutoresizingMaskIntoConstraints = true
                window?.contentView = hostingView
            }
        } else {
            // Not transparent: no visual effect view, just the hosting view
            let cornerRadius: CGFloat
            if #available(macOS 26.0, *) {
                cornerRadius = DesignSystem.standardCornerRadius
            } else {
                cornerRadius = 12
            }
            hostingView.layer?.cornerRadius = cornerRadius
            hostingView.layer?.masksToBounds = true
            hostingView.translatesAutoresizingMaskIntoConstraints = true
            window?.contentView = hostingView
        }

        if heightObserver == nil {
            heightObserver = hostingView.observe(\.frame) { [weak self] view, _ in
                let contentHeight = view.frame.height
                self?.updateWindowHeight(contentHeight)
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.setupTrackingArea()
        }
    }

    private func updateWindowHeight(_ contentHeight: CGFloat) {
        guard !isResizing, !isHeightFrozen, let window = window else { return }

        window.minSize = NSSize(width: defaultWidth, height: minHeight)
        window.maxSize = NSSize(width: defaultWidth, height: maxHeight)

        let newHeight = min(max(contentHeight, minHeight), maxHeight)
        var frame = window.frame
        frame.origin.y += frame.height - newHeight
        frame.size.height = newHeight

        // print(frame.size.height, "height")

        NSAnimationContext.runAnimationGroup { context in
            // 将动画时长从0.0改为0.2秒，创建平滑过渡效果
            context.duration = 0.2
            // 设置缓动函数使动画更自然
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        }
    }

    func freezeHeight() {
        isHeightFrozen = true
    }

    func unfreezeHeight() {
        isHeightFrozen = false
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

        // 使用透明度动画实现淡入效果
        window.alphaValue = 0.0
        super.showWindow(sender)

        // 让窗口成为 key window，并将它置于最前面
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // 动画淡入窗口
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 1.0
        })
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
        clearTrackingArea()
        NotificationCenter.default.removeObserver(self)

        if let monitor = optionKeyTapMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let globalMonitor = globalOptionKeyTapMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        WindowManager.shared.closeWindow(self)
    }

    private func setupOptionKeyMonitor() {
        // 局部监控：当 App 已聚焦时捕获事件
        optionKeyTapMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.checkDoubleOptionKey(event)
            return event
        }

        // 全局监控：无论 App 是否聚焦都捕获事件
        globalOptionKeyTapMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.checkDoubleOptionKey(event)
        }
    }

    // 公共方法：执行 Quick wake-up 逻辑
    private func performQuickWakeup() {
        let wasHidden = !(self.window?.isVisible ?? false)
        self.toggleWindow()
        if wasHidden {
            HotkeyCounter.shared.increment()
        }
    }

    private func checkDoubleOptionKey(_ event: NSEvent) {
        checkTripleOptionKey(event)
    }
}
