import AppKit
import Carbon
import ServiceManagement
import SwiftUI

@main
struct Hyper_NoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
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
}

class AppDelegate: NSObject, NSApplicationDelegate {
    //    let updater = AutoUpdater()
    private var windowController: MainWindowController?
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private var limitExceededWindow: LimitExceededWindowController?
    //    let hotkeyCounter = HotkeyCounter()

    func applicationDidFinishLaunching(_ notification: Notification) {

        // 设置为普通应用
        NSApp.setActivationPolicy(.accessory)

        // 初始化主窗口
        setupMainWindow()

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
                if HotkeyCounter.shared.todayCount >= AppConfig.QuickWakeup.dailyLimit {
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

    //    func application(_ application: NSApplication, open urls: [URL]) {
    //        guard let url = urls.first else { return }
    //
    //        // Check if this is an OAuth callback
    //        if url.scheme == "hypernote" && url.host == "oauth" && url.path == "/callback" {
    //            if let code = FeishuAuthManager.handleAuthCallback(url: url) {
    //                // Successfully got the authorization code
    //                print("✅ Received auth code:", code)
    //
    //                // Exchange the code for access token
    //                Task {
    //                    do {
    //                        let tokenResponse = try await FeishuAuthManager.getAccessToken(code: code)
    //
    //                        // Configure FeishuAPI with the new access token and expiration
    //                        FeishuAPI.shared.configure(
    //                            accessToken: tokenResponse.accessToken,
    //                            expiresIn: tokenResponse.expiresIn
    //                        )
    //                        FeishuAPI.shared.isEnabled = true
    //
    //                        // Show success notification
    //                        DispatchQueue.main.async {
    //                            let notification = NSUserNotification()
    //                            notification.title = "Authorization Successful"
    //                            notification.informativeText = "Successfully connected to Feishu"
    //                            NSUserNotificationCenter.default.deliver(notification)
    //                        }
    //                    } catch {
    //                        print("❌ Failed to get access token:", error)
    //
    //                        // Show error notification
    //                        DispatchQueue.main.async {
    //                            let notification = NSUserNotification()
    //                            notification.title = "Authorization Failed"
    //                            notification.informativeText =
    //                                "Failed to connect to Feishu: \(error.localizedDescription)"
    //                            NSUserNotificationCenter.default.deliver(notification)
    //                        }
    //                    }
    //                }
    //            } else {
    //                // Handle error
    //                let notification = NSUserNotification()
    //                notification.title = "Authorization Failed"
    //                notification.informativeText = "Failed to connect to Feishu"
    //                NSUserNotificationCenter.default.deliver(notification)
    //            }
    //        }
    //    }
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
