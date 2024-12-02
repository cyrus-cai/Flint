import Foundation
import AppKit
import SwiftUI

class WindowManager {
    static let shared = WindowManager()
    private var windows: [MainWindowController] = []
    
    func createNewWindow() {
        let windowController = MainWindowController()
        windows.append(windowController)
        windowController.showWindow(nil)
        
        // 设置新窗口位置（稍微错开）
        if let lastWindow = windows.dropLast().last,
           let frame = lastWindow.window?.frame {
            windowController.window?.setFrameOrigin(NSPoint(
                x: frame.origin.x + 20,
                y: frame.origin.y - 20
            ))
        }
    }
    
    func createSettingsWindow() {
           SettingsWindowController.shared.showWindow(nil)
       }
    
    
    func closeWindow(_ windowController: MainWindowController) {
        if let index = windows.firstIndex(where: { $0 === windowController }) {
            windows.remove(at: index)
        }
    }
}

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        super.init(window: window)
        
        window.center()
        window.title = "设置"
        window.contentView = NSHostingView(rootView: SettingsView())
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
                .resizable
            ],
            backing:.buffered,
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
            .transient
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
        visualEffectView.material = .sidebar
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
                visualEffectView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
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
              let zoomButton = window.standardWindowButton(.zoomButton) else { return }
        
        minimizeButton.isHidden = true
        zoomButton.isHidden=true
        closeButton.contentTintColor = .systemGray

        setButtonsAlpha(0)
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
        
            print(frame.size.height,"height")
            
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
            showWindow()
        }
    }
    
    private func showWindow() {
        guard let window = window else { return }
        
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
        UserDefaults.standard.set(["width": size.width, "height": size.height], forKey: "WindowSize")
    }
    
    private func loadSavedSize() -> NSSize? {
        guard let sizeData = UserDefaults.standard.object(forKey: "WindowSize") as? [String: CGFloat],
              let width = sizeData["width"],
              let height = sizeData["height"] else {
            return nil
        }
        return NSSize(width: width, height: height)
    }
    
    // MARK: - Position Management
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
    
    @objc private func windowDidMove(_ notification: Notification) {
        savePosition()
    }
    
    @objc private func windowDidBecomeKey(_ notification: Notification) {
        window?.level = .floating
    }
    
    deinit {
        if let trackingArea = trackingArea,
           let contentView = window?.contentView {
            contentView.removeTrackingArea(trackingArea)
        }
        NotificationCenter.default.removeObserver(self)
        WindowManager.shared.closeWindow(self)
    }
}
