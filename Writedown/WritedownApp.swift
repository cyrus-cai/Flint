import AppKit
import Carbon
//import ClerkSDK
import Cocoa
import KeyboardShortcuts
import Mixpanel
import ServiceManagement
import SwiftUI

@main
struct WritedownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        registerDefaultSettings()
        // Initialize Mixpanel with proper configuration
        Mixpanel.initialize(
            token: "f7863b6d43e142d2a35285b4d7764792",
            //            trackAutomaticEvents: false,  // Disable automatic event tracking
            flushInterval: 60  // Set flush interval to 60 seconds
        )

        // Enable debug logging in development
        #if DEBUG
            Mixpanel.mainInstance().loggingEnabled = true
        #endif

        // Set EU data residency if needed
        // Mixpanel.mainInstance().serverURL = "https://api-eu.mixpanel.com"

        // Disable IP-based geolocation if needed
        Mixpanel.mainInstance().useIPAddressForGeoLocation = false
    }

    var body: some Scene {
        // 使用 Settings scene，这样窗口只会在用户主动打开设置时显示
        Settings {
            SettingsView()
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    WindowManager.shared.createSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

class HotkeyCounter: ObservableObject {
    static let shared = HotkeyCounter()

    @Published private(set) var todayCount: Int
    private var midnightTimer: Timer?

    private init() {
        self.todayCount = Self.loadTodayCount()
        scheduleMidnightCheck()
    }

    private static func loadTodayCount() -> Int {
        if !isNewDay() {
            return UserDefaults.standard.integer(forKey: "hotkeyCount")
        }
        return 0
    }

    private static func isNewDay() -> Bool {
        guard let lastDate = UserDefaults.standard.object(forKey: "lastHotkeyDate") as? Date else {
            return true
        }
        return !Calendar.current.isDate(lastDate, inSameDayAs: Date())
    }

    private func scheduleMidnightCheck() {
        // 取消现有的定时器
        midnightTimer?.invalidate()

        // 计算下一个午夜的时间
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()),
            let nextMidnight = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: tomorrow)
        else {
            return
        }

        // 设置新的定时器
        midnightTimer = Timer(fire: nextMidnight, interval: 86400, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.resetCount()
            }
        }

        // 将定时器添加到 RunLoop
        RunLoop.main.add(midnightTimer!, forMode: .common)
    }

    private func resetCount() {
        todayCount = 0
        UserDefaults.standard.set(0, forKey: "hotkeyCount")
        UserDefaults.standard.set(Date(), forKey: "lastHotkeyDate")
    }

    func increment() {
        if Self.isNewDay() {
            todayCount = 1
        } else {
            todayCount += 1
        }

        // 保存到 UserDefaults
        UserDefaults.standard.set(todayCount, forKey: "hotkeyCount")
        UserDefaults.standard.set(Date(), forKey: "lastHotkeyDate")
    }

    deinit {
        midnightTimer?.invalidate()
    }

    var underLimit: Bool {
        return true  // Pro users have unlimited access
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSUserNotificationCenterDelegate {
    //    let updater = AutoUpdater()
    // private var windowController: MainWindowController? // Removed to use WindowManager
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private var limitExceededWindow: LimitExceededWindowController?
    var globalKeyMonitor: GlobalKeyMonitor?

    /// 订阅管理器 - 集中管理订阅状态
    private let subscriptionManager = SubscriptionManager.shared

    private func updateAppearance(_ mode: AppearanceMode) {
        if let window = NSApp.windows.first {
            switch mode {
            case .system:
                window.appearance = nil
            case .light:
                window.appearance = NSAppearance(named: .aqua)
            case .dark:
                window.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }
    //    let hotkeyCounter = HotkeyCounter()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Track app launch
        Mixpanel.mainInstance().track(event: "App Launched")
        UpdateManager.shared.checkAndDownloadUpdate()
        MaybeLikeService.shared.startMonitoring()

        // 订阅状态由 SubscriptionManager 自动管理
        // SubscriptionManager.shared 在初始化时会自动验证订阅状态
        // 并在应用激活时自动重新验证（带缓存）
        _ = subscriptionManager  // 触发 lazy 初始化

        // 设置为普通应用
        NSApp.setActivationPolicy(.accessory)
        NSUserNotificationCenter.default.delegate = self
        globalKeyMonitor = GlobalKeyMonitor()

        // 检查是否需要显示引导页
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

        if hasCompletedOnboarding {
            // 如果已完成引导，正常初始化
            setupMainWindow()
        } else {
            // 如果未完成引导，只显示引导页
            WindowManager.shared.showOnboardingIfNeeded()
        }

        // 设置快捷键
        setupGlobalHotkey()

        // Check if we should request launch permission
        if UserDefaults.standard.bool(forKey: "launchAtLogin")
            && !UserDefaults.standard.bool(forKey: "hasRequestedPermission")
        {
            LoginManager.shared.requestLaunchPermission { granted in
                if !granted {
                    UserDefaults.standard.set(false, forKey: "launchAtLogin")
                }
                UserDefaults.standard.set(true, forKey: "hasRequestedPermission")
            }
        }

        setupStatusBarItem()

        // Apply saved appearance setting
        if let appearanceMode = AppearanceMode(
            rawValue: UserDefaults.standard.string(forKey: "appearanceMode") ?? "System")
        {
            NSApp.windows.forEach { window in
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
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
        -> Bool
    {
        if !flag {
            WindowManager.shared.activeWindow?.showWindow(nil)
        }
        return true
    }

    private func setupMainWindow() {
        WindowManager.shared.createOrShowMainWindow()
    }

    @objc func toggleWindow() {
        WindowManager.shared.activeWindow?.toggleWindow()
        // Track window toggle
        Mixpanel.mainInstance().track(event: "Window Toggled")
    }

    private func setupGlobalHotkey() {
        KeyboardShortcuts.onKeyUp(for: .quickWakeup) { [weak self] in
            if HotkeyCounter.shared.todayCount >= AppConfig.QuickWakeup.dailyLimit
                && !UserDefaults.standard.bool(forKey: "isPro")
            {
                // Check if limit exceeded window is already shown
                if self?.limitExceededWindow == nil {
                    // Create and show limit exceeded window
                    let window = LimitExceededWindowController()
                    window.showWindow(nil)
                    NSApp.activate(ignoringOtherApps: true)
                    self?.limitExceededWindow = window

                    // Add window close observer
                    NotificationCenter.default.addObserver(
                        self as Any,
                        selector: #selector(self?.limitExceededWindowDidClose),
                        name: NSWindow.willCloseNotification,
                        object: window.window
                    )
                }
            } else {
                let wasHidden = WindowManager.shared.activeWindow?.window?.isVisible == false
                self?.toggleWindow()
                if wasHidden {
                    HotkeyCounter.shared.increment()
                    print("Shortcut count increased - window was hidden")
                }
            }
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

    private func setupStatusBarItem() {
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "note", accessibilityDescription: "Writedown")
            button.target = self
            button.action = #selector(statusBarButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!

        if event.type == .rightMouseUp {
            // Show context menu
            let menu = NSMenu()

            // macOS 26+ 新设计: 菜单项添加 SF Symbols 图标
            let openAppItem = NSMenuItem(
                title: "Open Writedown", action: #selector(toggleWindow), keyEquivalent: "")
            openAppItem.target = self
            openAppItem.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "Open")
            menu.addItem(openAppItem)

            let settingsItem = NSMenuItem(
                title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
            settingsItem.target = self
            settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: "Settings")
            menu.addItem(settingsItem)

            menu.addItem(NSMenuItem.separator())

            let quitItem = NSMenuItem(
                title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")
            menu.addItem(quitItem)

            statusItem?.menu = menu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else {
            // Left click - Quick wake up
            if HotkeyCounter.shared.underLimit || UserDefaults.standard.bool(forKey: "isPro") {
                toggleWindow()
                HotkeyCounter.shared.increment()
            } else {
                WindowManager.shared.createLimitExceededWindow()
            }
        }
    }

    @objc private func openApp() {
        if let activeWindow = WindowManager.shared.activeWindow {
            activeWindow.toggleWindow()
        } else {
            WindowManager.shared.createOrShowMainWindow()
        }
    }

    @objc private func openSettings() {
        WindowManager.shared.createSettingsWindow()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else {
            print("❌ No URL received")
            return
        }

        // Remove the Mixpanel initialization from here since it's now in WritedownApp.init()

        print("📥 Received URL: \(url)")

        // Check if this is a login callback
        // Login logic removed as per request
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
            components.queryItems?.contains(where: { $0.name == "session_id" }) == true
        {
            // New payment callback handling
            handleStripeCallback(url: url)
        } else {
             // print("❌ Invalid URL format - Expected writedown://oauth/callback")
        }
    }

    func handleStripeCallback(url: URL) {
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
            let sessionId = components.queryItems?.first(where: { $0.name == "session_id" })?.value
        {
            print("💳 Received Stripe session ID:", sessionId)

            // Verify the payment status with your backend
            Task {
                do {
                    let verifyURL = URL(
                        string: "https://www.writedown.space/verify-payment?session_id=\(sessionId)"
                    )!
                    let (data, response) = try await URLSession.shared.data(from: verifyURL)

                    if let httpResponse = response as? HTTPURLResponse,
                        httpResponse.statusCode == 200,
                        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                        let status = json["status"] as? String,
                        status == "success"
                    {
                        // Track successful payment
                        Mixpanel.mainInstance().track(event: "Payment Successful")
                        Mixpanel.mainInstance().people.set(property: "isPro", to: true)

                        // Update subscription status in UserDefaults
                        await MainActor.run {
                            let defaults = UserDefaults.standard
                            defaults.set(true, forKey: "isPro")
                            defaults.synchronize()

                            // Post notification to update UI
                            NotificationCenter.default.post(
                                name: NSNotification.Name("SubscriptionDidUpdate"),
                                object: nil
                            )

                            // Show success notification
                            let notification = NSUserNotification()
                            notification.title = "Payment Successful"
                            notification.informativeText = "Welcome to Writedown Pro!"
                            NSUserNotificationCenter.default.deliver(notification)
                        }
                    } else {
                        print("❌ Payment verification failed: Invalid response")
                    }
                } catch {
                    print("❌ Payment verification failed:", error)
                }
            }
        }
    }

    // MARK: - NSUserNotificationCenterDelegate
    func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
        if notification.activationType == .contentsClicked {
            if let userInfo = notification.userInfo,
               let filePath = userInfo["filePath"] as? String,
               let content = userInfo["content"] as? String {
                let fileURL = URL(fileURLWithPath: filePath)

                // If there is no active note window, create one using the window manager.
                if WindowManager.shared.activeWindow == nil {
                    WindowManager.shared.createNewWindow()
                }

                // Bring the main note window to the front.
                if let noteWindowController = WindowManager.shared.activeWindow as? MainWindowController {
                    noteWindowController.showWindow(nil)
                    NSApp.activate(ignoringOtherApps: true)

                    // Post notification to update ContentView
                    NotificationCenter.default.post(
                        name: Notification.Name("LoadNoteNotification"),
                        object: nil,
                        userInfo: ["content": content, "fileURL": fileURL]
                    )
                }
            }
        }
    }
}

// MARK: - HotKey Implementation
class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handler: () -> Void

    init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler

        // 注册回调函数
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // 创建事件处理器
        var handlerRef: EventHandlerRef?
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let handlerCallback: EventHandlerUPP = { _, eventRef, userData in
            //            guard let eventRef = eventRef else { return OSStatus(eventNotHandledErr) }
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }

            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            hotKey.handler()

            return noErr
        }

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            handlerCallback,
            1,
            &eventType,
            selfPtr,
            &handlerRef
        )

        guard status == noErr else { return nil }

        // 注册热键
        //        var hotKeyID = EventHotKeyID(signature: OSType(0x4850524E), // "HPRN"
        //                                   id: 1)
        let hotKeyID = EventHotKeyID(
            signature: OSType(0x4850_524E),  // "HPRN"
            id: 1)

        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else { return nil }
    }

    deinit {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
    }
}

class GlobalKeyMonitor {
    private var monitor: Any?
    private var lastCommandCPress: Date?
    // 定义双击的最大时间间隔（秒）
    private let doublePressThreshold: TimeInterval = 0.3

    init() {
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    func startMonitoring() {
        // 注意：全局监听需要辅助功能权限
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event: event)
        }
    }

    func stopMonitoring() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handle(event: NSEvent) {
        // 判断是否按下了 Command 键以及字符是否为 "c"
        if event.modifierFlags.contains(.command),
            let characters = event.charactersIgnoringModifiers,
            characters.lowercased() == "c"
        {
            let now = Date()
            if let lastPress = lastCommandCPress,
                now.timeIntervalSince(lastPress) < doublePressThreshold
            {
                // 检测到双击 Command+C 事件
                saveClipboardContent()
            }
            lastCommandCPress = now
        }
    }

    private func saveClipboardContent() {
        guard let clipboardContent = NSPasteboard.general.string(forType: .string) else {
            return
        }

        // Get the frontmost application name
        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"

        // Create title for the note
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let title = dateFormatter.string(from: Date())

        do {
            // Get file URL for saving
            let fileURL = LocalFileManager.shared.fileURL(for: title)
            guard let fileURL = fileURL else {
                throw NSError(
                    domain: "FileError",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid file URL"]
                )
            }

            // Add source app information as a metadata line at the beginning of the file
            let textWithMetadata = "<!-- Source: \(sourceApp) -->\n\(clipboardContent)"

            // Write content to file
            try textWithMetadata.write(to: fileURL, atomically: true, encoding: .utf8)
            print("Saved clipboard content to: \(fileURL.path)")

            // 增加使用次数统计
            HotkeyCounter.shared.increment()

            // Create and deliver system notification
            let notification = NSUserNotification()
            notification.title = "Content Saved"
            notification.subtitle = "From \(sourceApp)"
            notification.informativeText = "\(clipboardContent.count) chars saved"
            notification.soundName = NSUserNotificationDefaultSoundName
            notification.userInfo = ["filePath": fileURL.path, "content": textWithMetadata]
            
            NSUserNotificationCenter.default.deliver(notification)
        } catch {
            print("Save failed: \(error.localizedDescription)")
        }
    }
}

// 自定义一个不可激活的窗口，防止抢占焦点
class NonActivatingWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

class ContentSavedWindowController: NSWindowController {
    // private var windowController: MainWindowController?
    // Store the clipboard content for later use
    private let clipboardContent: String
    private let sourceApp: String
    private let charCount: Int
    private let fileURL: URL

    // Remove unused property
    // private var windowController: MainWindowController?

    @objc func toggleWindow() {
         WindowManager.shared.activeWindow?.toggleWindow()
    }

    init(position: NSRect, clipboardContent: String, sourceApp: String, charCount: Int, fileURL: URL) {
        self.clipboardContent = clipboardContent
        self.sourceApp = sourceApp
        self.charCount = charCount
        self.fileURL = fileURL

        let windowFrame = NSRect(
            x: position.origin.x,
            y: position.origin.y,
            width: 360,
            height: 64
        )
        let window = NonActivatingWindow(
            contentRect: windowFrame,
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        window.level = .statusBar + 1
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true

        super.init(window: window)

        let contentView = NSView(frame: window.contentView?.bounds ?? windowFrame)
        contentView.wantsLayer = true

        // macOS 26+ Liquid Glass 适配
        if #available(macOS 26.0, *) {
            // macOS 26+: 使用更现代的视觉效果
            // 当 Xcode 26 SDK 可用时，可以替换为 NSGlassEffectView
            let visualEffectView = NSVisualEffectView(frame: contentView.bounds)
            visualEffectView.material = .hudWindow
            visualEffectView.blendingMode = .behindWindow
            visualEffectView.state = .active
            visualEffectView.wantsLayer = true
            visualEffectView.layer?.cornerRadius = DesignSystem.standardCornerRadius
            contentView.addSubview(visualEffectView)
            
            visualEffectView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                visualEffectView.topAnchor.constraint(equalTo: contentView.topAnchor),
                visualEffectView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                visualEffectView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                visualEffectView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
            
            contentView.layer?.cornerRadius = DesignSystem.standardCornerRadius
        } else {
            // macOS 15-25: 添加传统毛玻璃效果视图
            let visualEffectView = NSVisualEffectView(frame: contentView.bounds)
            visualEffectView.material = .windowBackground
            visualEffectView.blendingMode = .behindWindow
            visualEffectView.state = .active
            visualEffectView.wantsLayer = true
            visualEffectView.layer?.cornerRadius = 16
            contentView.addSubview(visualEffectView)

            visualEffectView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                visualEffectView.topAnchor.constraint(equalTo: contentView.topAnchor),
                visualEffectView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                visualEffectView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                visualEffectView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
            
            contentView.layer?.cornerRadius = 16
        }
        
        contentView.layer?.masksToBounds = true
        window.contentView = contentView

        // 修改文本颜色，使用系统默认颜色以适配当前主题
        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        // Icon image view
        let iconImageView = NSImageView()
        if let appIcon = NSImage(named: "AppIcon") {
            iconImageView.image = appIcon
        }
        iconImageView.imageScaling = .scaleProportionallyDown
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconImageView.widthAnchor.constraint(equalToConstant: 32),
            iconImageView.heightAnchor.constraint(equalToConstant: 32),
        ])

        // Text stack view containing title and subtitle
        let textStackView = NSStackView()
        textStackView.orientation = .vertical
        textStackView.spacing = 2
        textStackView.alignment = .leading

        let titleLabel = NSTextField(labelWithString: "Content Saved")
        titleLabel.textColor = .labelColor  // 使用系统标签颜色
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)

        let displayText = "From \(sourceApp) | \(charCount) chars"

        let subtitleLabel = NSTextField(labelWithString: displayText)
        subtitleLabel.textColor = .secondaryLabelColor  // 使用系统次要标签颜色
        subtitleLabel.font = .systemFont(ofSize: 13)

        textStackView.addArrangedSubview(titleLabel)
        textStackView.addArrangedSubview(subtitleLabel)

        stackView.addArrangedSubview(iconImageView)
        stackView.addArrangedSubview(textStackView)

        let spacerView = NSView()
        spacerView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stackView.addArrangedSubview(spacerView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])

        // Add click gesture to the content view
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(viewClicked))
        contentView.addGestureRecognizer(clickGesture)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func viewClicked() {
        // Close the notification window.
        self.close()

        // If there is no active note window, create one using the window manager.
        if WindowManager.shared.activeWindow == nil {
            WindowManager.shared.createNewWindow()
        }

        // Bring the main note window to the front.
        if let noteWindowController = WindowManager.shared.activeWindow as? MainWindowController {
            noteWindowController.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)

            // Post notification to update ContentView
            NotificationCenter.default.post(
                name: Notification.Name("LoadNoteNotification"),
                object: nil,
                userInfo: ["content": clipboardContent, "fileURL": fileURL]
            )
        }
    }

    // When the "View" button is clicked, close this notification window,
    // show the main note window, and load the saved note content.
    @objc private func viewButtonClicked(_ sender: NSButton) {
        // Close the notification window.
        self.close()

        // If there is no active note window, create one using the window manager.
        if WindowManager.shared.activeWindow == nil {
            WindowManager.shared.createNewWindow()
        }

        // Bring the main note window to the front.
        if let noteWindowController = WindowManager.shared.activeWindow as? MainWindowController {
            noteWindowController.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)

            // Load the saved clipboard content into the main note window's content view.
            if let hostingController = noteWindowController.contentViewController
                as? NSHostingController<ContentView>
            {
                hostingController.rootView.loadNoteContent(clipboardContent)
            }
        }
    }

    // This method shows the window with a slide-in from the right animation.
    override func showWindow(_ sender: Any?) {
        guard let window = self.window,
            let screen = window.screen ?? NSScreen.main
        else {
            super.showWindow(sender)
            return
        }
        // The final frame is what we originally set in the initializer.
        let finalFrame = window.frame

        // Create an initial frame off-screen at the right.
        var initialFrame = finalFrame
        initialFrame.origin.x = screen.visibleFrame.maxX
        window.setFrame(initialFrame, display: false)
        window.alphaValue = 0.0

        super.showWindow(sender)

        // Animate the window sliding in from the right.
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.3
                window.animator().alphaValue = 1.0
                window.animator().setFrame(finalFrame, display: true)
            },
            completionHandler: {
                // After the window is visible, keep it on screen for a few seconds
                // then animate it out.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.animateWindowOutAndClose(finalFrame: finalFrame)
                }
            })
    }

    // Animate the window moving offscreen to the right and closing.
    private func animateWindowOutAndClose(finalFrame: NSRect) {
        guard let window = self.window,
            let screen = window.screen ?? NSScreen.main
        else {
            self.close()
            return
        }
        var offScreenFrame = finalFrame
        offScreenFrame.origin.x = screen.visibleFrame.maxX
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.5
                window.animator().alphaValue = 0.0
                window.animator().setFrame(offScreenFrame, display: true)
            },
            completionHandler: {
                self.close()
            })
    }
}

private func registerDefaultSettings() {
    let defaults: [String: Any] = [
        "enableAIRename": true,
        // Other default settings can be added here
    ]

    UserDefaults.standard.register(defaults: defaults)
}
