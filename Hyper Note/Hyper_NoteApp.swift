//import SwiftUI
//import Carbon
//
//@main
//struct Hyper_NoteApp: App {
//    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
//    
//    var body: some Scene {
//        Settings { // 将 WindowGroup 改为 Settings
//            EmptyView()
//        }
//    }
//}
//
//class AppDelegate: NSObject, NSApplicationDelegate {
//    private var windowController: MainWindowController?
//    private var statusItem: NSStatusItem?
//    private var hotKey: HotKey?  // 添加热键存储属性
//    
//    func applicationDidFinishLaunching(_ notification: Notification) {
//        // 设置为普通应用
//        NSApp.setActivationPolicy(.regular)
//        
//        // 初始化主窗口
//        setupMainWindow()
//        
//        // 设置状态栏
//        setupStatusItem()
//        
//        // 设置快捷键
//        setupGlobalHotkey()
//    }
//    
//    // 添加处理 Dock 点击事件的方法
//    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
//        if !flag {
//            windowController?.showWindow(nil)
//        }
//        return true
//    }
//    
//    private func setupMainWindow() {
//        windowController = MainWindowController()
//        windowController?.showWindow(nil)
//    }
//    
//    private func setupStatusItem() {
//        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
//        
//        if let button = statusItem?.button {
//            button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Hyper Note")
//            
//            let menu = NSMenu()
//            menu.addItem(NSMenuItem(title: "Show/Hide", action: #selector(toggleWindow), keyEquivalent: ""))
//            menu.addItem(NSMenuItem.separator())
//            menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
//            
//            statusItem?.menu = menu
//        }
//    }
//    
//    private func setupGlobalHotkey() {
//        // 创建快捷键：Option + C
//        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(optionKey), handler: { [weak self] in
//            self?.toggleWindow()
//        })
//    }
//    
//    @objc func toggleWindow() {
//        windowController?.toggleWindow()
//    }
//}
//
//// MARK: - HotKey Implementation
//class HotKey {
//    private var hotKeyRef: EventHotKeyRef?
//    private var handler: () -> Void
//    
//    init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
//        self.handler = handler
//        
//        // 注册回调函数
//        var eventType = EventTypeSpec(
//            eventClass: OSType(kEventClassKeyboard),
//            eventKind: UInt32(kEventHotKeyPressed)
//        )
//        
//        // 创建事件处理器
//        var handlerRef: EventHandlerRef?
//        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
//        
//        let handlerCallback: EventHandlerUPP = { _, eventRef, userData in
//            guard let eventRef = eventRef else { return OSStatus(eventNotHandledErr) }
//            guard let userData = userData else { return OSStatus(eventNotHandledErr) }
//            
//            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
//            hotKey.handler()
//            
//            return noErr
//        }
//        
//        let status = InstallEventHandler(
//            GetApplicationEventTarget(),
//            handlerCallback,
//            1,
//            &eventType,
//            selfPtr,
//            &handlerRef
//        )
//        
//        guard status == noErr else { return nil }
//        
//        // 注册热键
//        var hotKeyID = EventHotKeyID(signature: OSType(0x4850524E), // "HPRN"
//                                   id: 1)
//        
//        let registerStatus = RegisterEventHotKey(
//            keyCode,
//            modifiers,
//            hotKeyID,
//            GetApplicationEventTarget(),
//            0,
//            &hotKeyRef
//        )
//        
//        guard registerStatus == noErr else { return nil }
//    }
//    
//    deinit {
//        if let hotKeyRef = hotKeyRef {
//            UnregisterEventHotKey(hotKeyRef)
//        }
//    }
//}

import SwiftUI
import Carbon

@main
struct Hyper_NoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: MainWindowController?
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 设置深色模式
        NSApp.appearance = NSAppearance(named: .darkAqua)
        
        // 设置为普通应用
        NSApp.setActivationPolicy(.regular)
        
        // 初始化主窗口
        setupMainWindow()
        
        // 设置状态栏
        setupStatusItem()
        
        // 设置快捷键
        setupGlobalHotkey()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            windowController?.showWindow(nil)
        }
        return true
    }
    
    private func setupMainWindow() {
        windowController = MainWindowController()
        windowController?.window?.appearance = NSAppearance(named: .darkAqua)
        windowController?.showWindow(nil)
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Hyper Note")
            
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Show/Hide", action: #selector(toggleWindow), keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            
            statusItem?.menu = menu
        }
    }
    
    private func setupGlobalHotkey() {
        // 创建快捷键：Option + C
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(optionKey), handler: { [weak self] in
            self?.toggleWindow()
        })
    }
    
    @objc func toggleWindow() {
        windowController?.toggleWindow()
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
            guard let eventRef = eventRef else { return OSStatus(eventNotHandledErr) }
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
        var hotKeyID = EventHotKeyID(signature: OSType(0x4850524E), // "HPRN"
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
