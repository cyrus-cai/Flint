import AppKit
import Carbon
//import ClerkSDK
import Cocoa
import ServiceManagement
import SwiftUI

@main
struct WritedownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Check pro status on app launch if user is logged in
        if UserDefaults.standard.string(forKey: "userEmail") != nil {
            Task {
                do {
                    print(
                        "Checking pro status for \(UserDefaults.standard.string(forKey: "userEmail") ?? "nil")"
                    )
                    let isPro = try await ProStatusChecker.shared.checkProStatus(
                        email: UserDefaults.standard.string(forKey: "userEmail") ?? "")
                    print("Setting isPro to \(isPro)")
                    UserDefaults.standard.set(isPro, forKey: "isPro")
                } catch {
                    print("Pro status check failed: \(error)")
                    // Set to false when pro status check fails
                    UserDefaults.standard.set(false, forKey: "isPro")
                }
            }
        } else {
            // Set to false when not logged in
            UserDefaults.standard.set(false, forKey: "isPro")
        }

        // Observe login success notification
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("UserDidLogin"), object: nil, queue: .main
        ) { _ in
            Task {
                do {
                    let isPro = try await ProStatusChecker.shared.checkProStatus(
                        email: UserDefaults.standard.string(forKey: "userEmail") ?? "")
                    UserDefaults.standard.set(isPro, forKey: "isPro")
                } catch {
                    print("Pro status check failed: \(error)")
                    // Set to false when pro status check fails
                    UserDefaults.standard.set(false, forKey: "isPro")
                }
            }
        }
    }

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
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

class AppDelegate: NSObject, NSApplicationDelegate {
    //    let updater = AutoUpdater()
    private var windowController: MainWindowController?
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private var limitExceededWindow: LimitExceededWindowController?
    var globalKeyMonitor: GlobalKeyMonitor?
    //    let hotkeyCounter = HotkeyCounter()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 设置为普通应用
        NSApp.setActivationPolicy(.accessory)
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
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
        -> Bool
    {
        if !flag {
            windowController?.showWindow(nil)
        }
        return true
    }

    private func setupMainWindow() {
        windowController = MainWindowController()
        windowController?.showWindow(nil)
    }

    private func setupGlobalHotkey() {
        hotKey = HotKey(
            keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(optionKey),
            handler: { [weak self] in
                if HotkeyCounter.shared.todayCount >= AppConfig.QuickWakeup.dailyLimit
                    && !UserDefaults.standard.bool(forKey: "isPro")
                {
                    // 检查是否已经显示了限制窗口
                    if self?.limitExceededWindow == nil {
                        // 创建并显示限制窗口
                        let window = LimitExceededWindowController()
                        window.showWindow(nil)
                        NSApp.activate(ignoringOtherApps: true)
                        self?.limitExceededWindow = window

                        // 添加窗口关闭的观察
                        NotificationCenter.default.addObserver(
                            self as Any,
                            selector: #selector(self?.limitExceededWindowDidClose),
                            name: NSWindow.willCloseNotification,
                            object: window.window
                        )
                    }
                } else {
                    let wasHidden = self?.windowController?.window?.isVisible == false
                    self?.toggleWindow()
                    if wasHidden {
                        HotkeyCounter.shared.increment()
                        print("Shortcut count increased - window was hidden")
                    }
                }
            })
    }

    @objc private func limitExceededWindowDidClose(_ notification: Notification) {
        limitExceededWindow = nil
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.willCloseNotification,
            object: notification.object
        )
    }

    @objc func toggleWindow() {
        windowController?.toggleWindow()
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

            let openAppItem = NSMenuItem(
                title: "Open Writedown", action: #selector(toggleWindow), keyEquivalent: "")
            openAppItem.target = self
            menu.addItem(openAppItem)

            let settingsItem = NSMenuItem(
                title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
            settingsItem.target = self
            menu.addItem(settingsItem)

            menu.addItem(NSMenuItem.separator())

            let quitItem = NSMenuItem(
                title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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

        print("📥 Received URL: \(url)")

        // Check if this is a login callback
        if url.scheme == "writedown" && url.host == "oauth" && url.path == "/callback" {
            print("✅ Valid login callback URL")

            if let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
                let queryItems = components.queryItems
            {
                print("📋 Query items: \(queryItems)")

                // Extract user information from query parameters
                let email = queryItems.first(where: { $0.name == "email" })?.value
                let avatar = queryItems.first(where: { $0.name == "avatar" })?.value
                let name = queryItems.first(where: { $0.name == "name" })?.value

                print("👤 Extracted user info:")
                print("   Email: \(email ?? "nil")")
                print("   Name: \(name ?? "nil")")
                print("   Avatar: \(avatar ?? "nil")")

                // Store user information in UserDefaults
                let defaults = UserDefaults.standard
                if let email = email?.removingPercentEncoding {
                    defaults.set(email, forKey: "userEmail")
                    defaults.synchronize()
                }
                if let avatar = avatar?.removingPercentEncoding {
                    defaults.set(avatar, forKey: "userAvatar")
                    defaults.synchronize()
                }

                // Process name first
                let processedName =
                    name?.removingPercentEncoding?.replacingOccurrences(
                        of: "+", with: " ") ?? ""

                if !processedName.isEmpty {
                    defaults.set(processedName, forKey: "userName")
                    defaults.synchronize()
                }

                print("💾 User info saved to UserDefaults")

                // 主动打开设置窗口并更新状态
                DispatchQueue.main.async {
                    WindowManager.shared.createSettingsWindow()

                    // Post notification to update UI
                    NotificationCenter.default.post(
                        name: NSNotification.Name("UserDidLogin"),
                        object: nil
                    )
                    print("📢 Posted UserDidLogin notification")

                    // Show success notification with processed name
                    let notification = NSUserNotification()
                    notification.title = "Login Successful"
                    notification.informativeText =
                        processedName.isEmpty ? "Welcome back!" : "Welcome back \(processedName)!"
                    NSUserNotificationCenter.default.deliver(notification)
                    print("🔔 Showed success notification")
                }
            } else {
                print("❌ Failed to parse URL components")
            }
        } else if let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
            components.queryItems?.contains(where: { $0.name == "session_id" }) == true
        {
            // New payment callback handling
            handleStripeCallback(url: url)
        } else {
            print("❌ Invalid URL format - Expected writedown://oauth/callback")
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
                        // Update subscription status in UserDefaults
                        DispatchQueue.main.async {
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
                    }
                } catch {
                    print("❌ Payment verification failed:", error)
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
        // 从剪贴板获取字符串内容
        guard let text = NSPasteboard.general.string(forType: .string) else {
            print("No clipboard content found.")
            return
        }

        print("剪贴板内容: \(text)")

        // 根据文本生成文件名
        var title: String {
            let firstLine = text.components(separatedBy: .newlines).first ?? ""
            return firstLine.isEmpty
                ? "Untitled" : (firstLine.count > 12 ? firstLine.prefix(12) + "..." : firstLine)
        }

        do {
            // 获取用于保存的文件 URL
            let fileURL = FileManager.shared.fileURL(for: title)
            guard let fileURL = fileURL else {
                throw NSError(
                    domain: "FileError",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid file URL"]
                )
            }

            // 写入剪贴板内容至文件
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            print("Saved clipboard content to: \(fileURL.path)")

            // 定义反馈窗口的默认尺寸
            let defaultWidth: CGFloat = 320
            let defaultHeight: CGFloat = 100

            // 展示 "Contents saved" 提示窗口
            if let noteWindowController = WindowManager.shared.activeWindow,
                let noteWindow = noteWindowController.window
            {
                // 如果存在活动窗口，则使用该窗口的位置，并垂直居中提示窗口
                let noteFrame = noteWindow.frame
                let feedbackFrame = NSRect(
                    x: noteFrame.origin.x,
                    y: noteFrame.origin.y + (noteFrame.height - defaultHeight) / 2,
                    width: noteFrame.width,
                    height: defaultHeight
                )
                let feedbackWindow = ContentSavedWindowController(position: feedbackFrame)
                feedbackWindow.showWindow(nil)
            } else {
                // 没有活动窗口时，使用默认位置（屏幕右上角）
                guard let screen = NSScreen.main else { return }
                let screenFrame = screen.visibleFrame
                let rightTopX = screenFrame.maxX - defaultWidth - 20
                let rightTopY = screenFrame.maxY - 20
                let feedbackFrame = NSRect(
                    x: rightTopX,
                    y: rightTopY - defaultHeight,
                    width: defaultWidth,
                    height: defaultHeight
                )
                let feedbackWindow = ContentSavedWindowController(position: feedbackFrame)
                feedbackWindow.showWindow(nil)
            }

            // 不再调用 NSApp.activate(ignoringOtherApps:)，确保反馈窗口不会改变当前应用的焦点
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
    init(position: NSRect) {
        let windowFrame = NSRect(
            x: position.origin.x,
            y: position.origin.y,
            width: position.width,
            height: 64
        )

        let window = NonActivatingWindow(
            contentRect: windowFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .statusBar + 1
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true

        super.init(window: window)

        // 创建主容器视图
        let contentView = NSView(frame: window.contentView?.bounds ?? windowFrame)
        contentView.wantsLayer = true
        // 使用系统深色模式下的背景色
        contentView.layer?.backgroundColor = NSColor(white: 0.17, alpha: 0.95).cgColor
        contentView.layer?.cornerRadius = 16
        contentView.layer?.masksToBounds = true
        window.contentView = contentView

        // 创建水平堆栈视图
        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        // 添加应用图标
        let iconImageView = NSImageView()
        if let appIcon = NSImage(named: "AppIcon") {  // 确保你的应用图标资源名称正确
            iconImageView.image = appIcon
        }
        iconImageView.imageScaling = .scaleProportionallyDown
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconImageView.widthAnchor.constraint(equalToConstant: 32),
            iconImageView.heightAnchor.constraint(equalToConstant: 32),
        ])

        // 创建文本堆栈视图
        let textStackView = NSStackView()
        textStackView.orientation = .vertical
        textStackView.spacing = 2
        textStackView.alignment = .leading

        // 添加主标题
        let titleLabel = NSTextField(labelWithString: "Content saved")
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        // 添加副标题
        let subtitleLabel = NSTextField(
            labelWithString: "Double-click ⌘C to save clipboard content")
        subtitleLabel.textColor = .white.withAlphaComponent(0.6)
        subtitleLabel.font = .systemFont(ofSize: 11)

        textStackView.addArrangedSubview(titleLabel)
        textStackView.addArrangedSubview(subtitleLabel)

        // 将图标和文本堆栈添加到主堆栈
        stackView.addArrangedSubview(iconImageView)
        stackView.addArrangedSubview(textStackView)

        // 设置堆栈视图约束
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.close()
        }
    }
}
