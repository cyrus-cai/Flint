import Foundation
import AppKit
import SwiftUI

class MainWindowController: NSWindowController {
    // 窗口默认尺寸
    private let defaultWidth: CGFloat = 400
    private let defaultHeight: CGFloat = 120
    
    // 用于跟踪窗口的事件监听
    private var trackingArea: NSTrackingArea?
    
    // MARK: - Initialization
    init() {
        // 创建窗口
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: defaultWidth, height: defaultHeight),
            styleMask: [
                .titled,
                .closable,
                .fullSizeContentView
            ],
            backing: .buffered,
            defer: false
        )
        
        // 调用父类初始化
        super.init(window: window)
        
        // 配置窗口
        configureWindow()
        // 设置内容视图
        setupContentView()
        // 设置窗口位置
        setupInitialPosition()
        
        // 注册通知
        setupNotifications()
        
        // 延迟设置跟踪区域，确保窗口完全加载
        DispatchQueue.main.async { [weak self] in
            self?.setupTrackingArea()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Window Configuration
    private func configureWindow() {
        guard let window = window else { return }
        
        // 基础设置
        window.title = "Hyper Note"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .clear
        window.hasShadow = true  // 确保窗口有阴影
        window.invalidateShadow()  // 刷新阴影

        window.level = .floating  // 改用 floating 级别
        window.collectionBehavior = [
               .canJoinAllSpaces,      // 允许在所有空间显示
               .fullScreenAuxiliary,   // 全屏时保持显示
               .stationary,            // 保持位置固定
               .transient             // 添加这个确保窗口跟随
           ]

        
        // 窗口行为
        window.level = .statusBar + 1
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = false
        
        // 允许在非激活状态下响应鼠标事件
        window.acceptsMouseMovedEvents = true
        
        // 窗口交互
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        
        // 窗口大小
        window.minSize = NSSize(width: defaultWidth, height: defaultHeight)
        window.maxSize = NSSize(width: defaultWidth, height: defaultHeight)
        
        // 确保视图正确显示
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 16
            contentView.layer?.masksToBounds = true
        }
        
        configureWindowButtons()
    }
    
    private func configureWindowButtons() {
        guard let window = window,
              let closeButton = window.standardWindowButton(.closeButton),
              let minimizeButton = window.standardWindowButton(.miniaturizeButton),
              let zoomButton = window.standardWindowButton(.zoomButton) else { return }
        
        // 禁用最小化按钮
        minimizeButton.isEnabled = false
        
        // 设置按钮颜色
        closeButton.contentTintColor = .systemRed
        minimizeButton.contentTintColor = .systemYellow
        zoomButton.contentTintColor = .systemGreen
        
        // 初始状态设置按钮为半透明
        setButtonsAlpha(0)
    }
    
    // MARK: - Mouse Tracking
    private func setupTrackingArea() {
        guard let contentView = window?.contentView else { return }
        
        // 移除已存在的跟踪区域
        if let existingTrackingArea = trackingArea {
            contentView.removeTrackingArea(existingTrackingArea)
        }
        
        // 创建新的跟踪区域，覆盖整个contentView
        let trackingArea = NSTrackingArea(
            rect: contentView.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        
        contentView.addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }
    
    // MARK: - Mouse Event Handling
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        setButtonsAlpha(1.0)
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setButtonsAlpha(0)
    }
    
    private func setButtonsAlpha(_ alpha: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            window?.standardWindowButton(.closeButton)?.animator().alphaValue = alpha
            window?.standardWindowButton(.miniaturizeButton)?.animator().alphaValue = alpha
            window?.standardWindowButton(.zoomButton)?.animator().alphaValue = alpha
        }
    }
    
    // MARK: - Content View Setup
    private func setupContentView() {
        let contentView = ContentView()
        let hostingController = NSHostingController(rootView: contentView)
        window?.contentViewController = hostingController
        
        // 监听contentView的frame变化，更新trackingArea
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentViewFrameDidChange),
            name: NSView.frameDidChangeNotification,
            object: window?.contentView
        )
    }
    
    @objc private func contentViewFrameDidChange(_ notification: Notification) {
        setupTrackingArea()
    }
    
    // MARK: - Window Position
    private func setupInitialPosition() {
        guard let window = window else { return }
        
        if let savedPosition = getSavedPosition() {
            // 使用保存的位置
            window.setFrameTopLeftPoint(savedPosition)
        } else {
            // 首次显示，设置在右上角
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
    
    // MARK: - Window State Management
    func toggleWindow() {
        guard let window = window else { return }
        
        if window.isVisible {
            hideWindow()
        } else {
            showWindow()
        }
    }
    
    private func showWindow() {
        guard let window = window else { return }
        
        // 确保窗口在可见位置
        if !isPositionVisible(window.frame.origin) {
            setDefaultPosition()
        }
        
        window.makeKeyAndOrderFront(nil)
        window.level = .statusBar + 1
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func hideWindow() {
        window?.orderOut(nil)
    }
    
    // MARK: - Position Management
    private func isPositionVisible(_ position: NSPoint) -> Bool {
        return NSScreen.screens.contains { screen in
            screen.frame.contains(position)
        }
    }
    
    private func getSavedPosition() -> NSPoint? {
        let defaults = UserDefaults.standard
        guard let positionData = defaults.object(forKey: "WindowPosition") as? [String: CGFloat],
              let x = positionData["x"],
              let y = positionData["y"] else {
            return nil
        }
        return NSPoint(x: x, y: y)
    }
    
    private func savePosition() {
        guard let position = window?.frame.origin else { return }
        let positionData: [String: CGFloat] = [
            "x": position.x,
            "y": position.y
        ]
        UserDefaults.standard.set(positionData, forKey: "WindowPosition")
    }
    
    // MARK: - Notifications
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove),
            name: NSWindow.didMoveNotification,
            object: window
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
    }
    
    @objc private func windowDidMove(_ notification: Notification) {
        savePosition()
    }
    
    @objc private func windowDidBecomeKey(_ notification: Notification) {
        window?.level = .floating  // 同样改用 floating 级别
    }
    
    // MARK: - Cleanup
    deinit {
        if let trackingArea = trackingArea,
           let contentView = window?.contentView {
            contentView.removeTrackingArea(trackingArea)
        }
        NotificationCenter.default.removeObserver(self)
    }
}
