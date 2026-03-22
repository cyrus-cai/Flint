import AppKit
import Carbon
import Cocoa
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

@main
struct FlintApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        registerDefaultSettings()
    }

    var body: some Scene {
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
        midnightTimer?.invalidate()

        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()),
            let nextMidnight = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: tomorrow)
        else {
            return
        }

        midnightTimer = Timer(fire: nextMidnight, interval: 86400, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.resetCount()
            }
        }

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

        UserDefaults.standard.set(todayCount, forKey: "hotkeyCount")
        UserDefaults.standard.set(Date(), forKey: "lastHotkeyDate")
    }

    deinit {
        midnightTimer?.invalidate()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem?
    var globalKeyMonitor: GlobalKeyMonitor?

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
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        UpdateManager.shared.checkAndDownloadUpdate()

        if UserDefaults.standard.bool(forKey: "enableAutoSaveClipboard") {
            MaybeLikeService.shared.startMonitoring()
        }

        NSApp.setActivationPolicy(.accessory)
        NSUserNotificationCenter.default.delegate = self
        globalKeyMonitor = GlobalKeyMonitor()

        // Initialize NotificationService for UserNotifications
        setupNotificationService()

        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

        if hasCompletedOnboarding {
            setupMainWindow()
        } else {
            WindowManager.shared.showOnboardingIfNeeded()
        }

        setupGlobalHotkey()

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
    }

    private func setupGlobalHotkey() {
        KeyboardShortcuts.onKeyUp(for: .quickWakeup) { [weak self] in
            let wasHidden = WindowManager.shared.activeWindow?.window?.isVisible == false
            self?.toggleWindow()
            if wasHidden {
                HotkeyCounter.shared.increment()
            }
        }
        
        KeyboardShortcuts.onKeyUp(for: .showRecentNotes) {
            WindowManager.shared.createOrShowMainWindow()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(
                    name: Notification.Name("ShowRecentNotesNotification"),
                    object: nil
                )
            }
        }
    }

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "note", accessibilityDescription: "Flint")
            button.target = self
            button.action = #selector(statusBarButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!

        if event.type == .rightMouseUp {
            let menu = NSMenu()

            let openAppItem = NSMenuItem(
                title: L("Open Flint"), action: #selector(toggleWindow), keyEquivalent: "")
            openAppItem.target = self
            openAppItem.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "Open")
            menu.addItem(openAppItem)

            let settingsItem = NSMenuItem(
                title: L("Settings"), action: #selector(openSettings), keyEquivalent: ",")
            settingsItem.target = self
            settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: "Settings")
            menu.addItem(settingsItem)

            menu.addItem(NSMenuItem.separator())

            let quitItem = NSMenuItem(
                title: L("Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")
            menu.addItem(quitItem)

            statusItem?.menu = menu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else {
            toggleWindow()
            HotkeyCounter.shared.increment()
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

    /// Setup UserNotifications service
    private func setupNotificationService() {
        Task {
            do {
                let granted = try await NotificationService.shared.requestAuthorization()
                if granted {
                    print("Notification permission granted")
                } else {
                    print("Notification permission denied")
                }
            } catch {
                print("Failed to request notification permission: \(error)")
            }
        }
    }

    func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
        if notification.activationType == .contentsClicked {
            if let userInfo = notification.userInfo,
               let filePath = userInfo["filePath"] as? String,
               let content = userInfo["content"] as? String {
                let fileURL = URL(fileURLWithPath: filePath)

                if WindowManager.shared.activeWindow == nil {
                    WindowManager.shared.createNewWindow()
                }

                if let noteWindowController = WindowManager.shared.activeWindow as? MainWindowController {
                    noteWindowController.showWindow(nil)
                    NSApp.activate(ignoringOtherApps: true)

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
            signature: OSType(0x464C_4E54),  // "HPRN"
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
        if event.isARepeat { return }

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
                lastCommandCPress = nil
            } else {
                lastCommandCPress = now
            }
        }
    }

    private func saveClipboardContent() {
        guard let clipboardContent = NSPasteboard.general.string(forType: .string) else {
            return
        }

        MaybeLikeService.shared.ignoreCurrentClipboardChange()

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
            let textWithMetadata = "<!-- Source: \(sourceApp) -->\n<!-- Type: HotKey -->\n\(clipboardContent)"

            // Write content to file
            try textWithMetadata.write(to: fileURL, atomically: true, encoding: .utf8)
            print("Saved clipboard content to: \(fileURL.path)")

            HotkeyCounter.shared.increment()

            Task {
                var summaryText = "\(clipboardContent.count) chars saved"
                
                // Try to get AI summary
                if MiniMaxAPI.hasConfiguredAPIKey {
                    let aiInput = MiniMaxAPI.prepareForAI(clipboardContent)
                    do {
                        let title = try await MiniMaxAPI.shared.generateTitle(text: aiInput)
                        if !title.isEmpty {
                            summaryText = title
                        }
                    } catch {
                        print("AI Summary failed for manual capture: \(error)")
                    }
                }
                
                let finalSummary = summaryText
                let finalFileURL = fileURL
                let finalTextWithMetadata = textWithMetadata
                let finalSourceApp = sourceApp
                
                // Send notification using NotificationService
                await NotificationService.shared.sendAIActionSuccess(
                    title: L("Content Saved"),
                    message: "\(finalSourceApp) | \(finalSummary)",
                    filePath: finalFileURL.path,
                    content: finalTextWithMetadata
                )
            }
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

        let titleLabel = NSTextField(labelWithString: L("Content Saved"))
        titleLabel.textColor = .labelColor  // 使用系统标签颜色
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)

        let displayText = String(format: L("From %@ | %d chars"), sourceApp, charCount)

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
        AppStorageKeys.enableAIRename: AppDefaults.enableAIRename,
        AppStorageKeys.enableAutoSaveClipboard: AppDefaults.enableAutoSaveClipboard,
        AppStorageKeys.AIModel: AppDefaults.AIModel,
    ]

    UserDefaults.standard.register(defaults: defaults)
}
