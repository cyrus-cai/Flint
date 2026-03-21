//
//  NotificationService.swift
//  Flint
//
//  Created by AI Agent on 1/22/26.
//

import UserNotifications
import AppKit

/// Service for managing UserNotifications (replacing deprecated NSUserNotification)
class NotificationService: NSObject {
    static let shared = NotificationService()
    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
    }

    // MARK: - Permission Handling

    /// Request notification permission
    func requestAuthorization() async throws -> Bool {
        let options: UNAuthorizationOptions = [.alert, .sound, .badge]
        return try await center.requestAuthorization(options: options)
    }

    /// Check current authorization status
    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    /// Whether notifications are authorized
    func isAuthorized() async -> Bool {
        let status = await checkAuthorizationStatus()
        return status == .authorized || status == .provisional
    }

    // MARK: - Notification Sending

    /// Send an immediate notification
    /// - Parameters:
    ///   - title: The notification title
    ///   - subtitle: Optional subtitle
    ///   - body: The notification body text
    ///   - userInfo: Optional user info dictionary
    ///   - timeSensitive: Whether the notification is time-sensitive (breaks through Focus mode)
    func sendNotification(
        title: String,
        subtitle: String? = nil,
        body: String,
        userInfo: [String: Any]? = nil,
        timeSensitive: Bool = false
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle = subtitle {
            content.subtitle = subtitle
        }
        content.body = body
        content.sound = .default

        if let userInfo = userInfo {
            // Convert to [AnyHashable: Any] for UNNotificationContent
            var contentUserInfo: [AnyHashable: Any] = [:]
            for (key, value) in userInfo {
                contentUserInfo[key] = value
            }
            content.userInfo = contentUserInfo
        }

        // Set interruption level for time-sensitive notifications (iOS 15+ / macOS 12+)
        if #available(macOS 12.0, *) {
            content.interruptionLevel = timeSensitive ? .timeSensitive : .active
        }

        // Create a trigger for immediate delivery
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)

        // Create the request
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        try await center.add(request)
        print("Notification sent: \(title)")
    }

    /// Send a success notification for AI agent action
    func sendAIActionSuccess(title: String, message: String, filePath: String? = nil, content: String? = nil) async {
        var userInfo: [String: Any] = [:]
        if let path = filePath {
            userInfo["filePath"] = path
        }
        if let content = content {
            userInfo["content"] = content
        }

        do {
            try await sendNotification(
                title: title,
                body: message,
                userInfo: userInfo.isEmpty ? nil : userInfo,
                timeSensitive: true
            )
        } catch {
            print("Failed to send notification: \(error)")
        }
    }

    /// Send a reminder created notification
    func sendReminderCreated(title: String, dueDate: Date) async {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        do {
            try await sendNotification(
                title: L("Reminder Created"),
                subtitle: title,
                body: String(format: L("Scheduled for %@"), formatter.string(from: dueDate)),
                timeSensitive: false
            )
        } catch {
            print("Failed to send reminder notification: \(error)")
        }
    }

    /// Send a calendar event created notification
    func sendCalendarEventCreated(title: String, startDate: Date) async {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        do {
            try await sendNotification(
                title: L("Event Created"),
                subtitle: title,
                body: String(format: L("Scheduled for %@"), formatter.string(from: startDate)),
                timeSensitive: false
            )
        } catch {
            print("Failed to send event notification: \(error)")
        }
    }

    /// Send an error notification
    func sendError(title: String, message: String) async {
        do {
            try await sendNotification(
                title: title,
                body: message,
                timeSensitive: false
            )
        } catch {
            print("Failed to send error notification: \(error)")
        }
    }

    // MARK: - Scheduled Notifications

    /// Schedule a notification for a future time
    /// - Parameters:
    ///   - identifier: Unique identifier for the notification
    ///   - title: The notification title
    ///   - body: The notification body text
    ///   - date: When to deliver the notification
    ///   - timeSensitive: Whether the notification is time-sensitive
    func scheduleNotification(
        identifier: String,
        title: String,
        body: String,
        date: Date,
        timeSensitive: Bool = true
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        if #available(macOS 12.0, *) {
            content.interruptionLevel = timeSensitive ? .timeSensitive : .active
        }

        let dateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        try await center.add(request)
        print("Scheduled notification '\(title)' for \(date)")
    }

    /// Cancel a scheduled notification
    func cancelNotification(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        print("Cancelled notification: \(identifier)")
    }

    /// Cancel all pending notifications
    func cancelAllNotifications() {
        center.removeAllPendingNotificationRequests()
        print("Cancelled all pending notifications")
    }

    // MARK: - Notification Management

    /// Get all pending notification requests
    func getPendingNotifications() async -> [UNNotificationRequest] {
        return await center.pendingNotificationRequests()
    }

    /// Get all delivered notifications
    func getDeliveredNotifications() async -> [UNNotification] {
        return await center.deliveredNotifications()
    }

    /// Remove all delivered notifications
    func removeAllDeliveredNotifications() {
        center.removeAllDeliveredNotifications()
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {
    /// Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        if #available(macOS 12.0, *) {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }

    /// Handle notification tap/interaction
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        // Handle notification tap
        if let filePath = userInfo["filePath"] as? String,
           let content = userInfo["content"] as? String {
            let fileURL = URL(fileURLWithPath: filePath)

            // Post notification to open the note
            DispatchQueue.main.async {
                // Use createOrShowMainWindow which handles both cases:
                // - If window exists, it shows it
                // - If window doesn't exist, it creates one
                WindowManager.shared.createOrShowMainWindow()

                NotificationCenter.default.post(
                    name: Notification.Name("LoadNoteNotification"),
                    object: nil,
                    userInfo: ["content": content, "fileURL": fileURL]
                )
            }
        }

        completionHandler()
    }
}
