import ApplicationServices
import Foundation
import ServiceManagement

class LoginManager {
    static let shared = LoginManager()

    func requestLaunchPermission(completion: @escaping (Bool) -> Void) {
        let options =
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: true] as CFDictionary
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        completion(accessEnabled)
    }

    func setLaunchAtLogin(enabled: Bool) {
        if enabled {
            enableLaunchAtLogin()
        } else {
            disableLaunchAtLogin()
        }
    }

    func enableLaunchAtLogin() {
        let bundleURL = Bundle.main.bundleURL

        do {
            if #available(macOS 13.0, *) {
                try SMAppService.mainApp.register()
            } else {
                // Fallback for older macOS versions
                if let loginItems = LSSharedFileListCreate(
                    nil, kLSSharedFileListSessionLoginItems.takeRetainedValue(), nil)
                {
                    let loginItemsRef = loginItems.takeRetainedValue()
                    LSSharedFileListInsertItemURL(
                        loginItemsRef,
                        kLSSharedFileListItemLast.takeRetainedValue(),
                        nil,
                        nil,
                        bundleURL as CFURL,
                        nil,
                        nil)
                }
            }
        } catch {
            print("Failed to register launch at login: \(error)")
        }
    }

    func disableLaunchAtLogin() {
        do {
            if #available(macOS 13.0, *) {
                try SMAppService.mainApp.unregister()
            } else {
                // Fallback for older macOS versions
                if let loginItems = LSSharedFileListCreate(
                    nil, kLSSharedFileListSessionLoginItems.takeRetainedValue(), nil)
                {
                    let loginItemsRef = loginItems.takeRetainedValue()
                    let bundleURL = Bundle.main.bundleURL

                    if let snapshot = LSSharedFileListCopySnapshot(loginItemsRef, nil)?
                        .takeRetainedValue() as? [LSSharedFileListItem]
                    {
                        for item in snapshot {
                            if let itemURL = LSSharedFileListItemCopyResolvedURL(item, 0, nil)?
                                .takeRetainedValue() as URL?,
                                itemURL == bundleURL
                            {
                                LSSharedFileListItemRemove(loginItemsRef, item)
                            }
                        }
                    }
                }
            }
        } catch {
            print("Failed to unregister launch at login: \(error)")
        }
    }
}
