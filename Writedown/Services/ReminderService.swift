//
//  ReminderService.swift
//  Writedown
//
//  Created by AI Agent on 1/22/26.
//

import EventKit
import Foundation

/// Service for managing reminders using EventKit
class ReminderService {
    static let shared = ReminderService()
    private let eventStore = EKEventStore()

    private init() {}

    // MARK: - Permission Handling

    /// Request access to Reminders
    func requestAccess() async throws -> Bool {
        if #available(macOS 14.0, *) {
            return try await eventStore.requestFullAccessToReminders()
        } else {
            return try await withCheckedThrowingContinuation { continuation in
                eventStore.requestAccess(to: .reminder) { granted, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
    }

    /// Check current authorization status
    var authorizationStatus: EKAuthorizationStatus {
        return EKEventStore.authorizationStatus(for: .reminder)
    }

    /// Whether reminders access is authorized
    var isAuthorized: Bool {
        let status = authorizationStatus
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        } else {
            return status == .authorized
        }
    }

    // MARK: - Reminder Creation

    /// Create a reminder with the given details
    /// - Parameters:
    ///   - title: The title of the reminder
    ///   - dueDate: When the reminder should trigger
    ///   - notes: Optional notes for the reminder
    /// - Returns: The identifier of the created reminder
    func createReminder(title: String, dueDate: Date, notes: String? = nil) async throws -> String {
        // Ensure we have access
        if !isAuthorized {
            let granted = try await requestAccess()
            guard granted else {
                throw ReminderServiceError.accessDenied
            }
        }

        // Get the default reminder calendar
        guard let calendar = eventStore.defaultCalendarForNewReminders() else {
            throw ReminderServiceError.noDefaultCalendar
        }

        // Create the reminder
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = calendar

        // Set the due date with alarm
        let dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: dueDate
        )
        reminder.dueDateComponents = dueDateComponents

        // Add an alarm at the due date
        let alarm = EKAlarm(absoluteDate: dueDate)
        reminder.addAlarm(alarm)

        // Save the reminder
        try eventStore.save(reminder, commit: true)

        print("Created reminder: \(title) at \(dueDate)")
        return reminder.calendarItemIdentifier
    }

    // MARK: - Calendar Event Creation

    /// Request access to Calendar
    func requestCalendarAccess() async throws -> Bool {
        if #available(macOS 14.0, *) {
            return try await eventStore.requestFullAccessToEvents()
        } else {
            return try await withCheckedThrowingContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
    }

    /// Check calendar authorization status
    var calendarAuthorizationStatus: EKAuthorizationStatus {
        return EKEventStore.authorizationStatus(for: .event)
    }

    /// Whether calendar access is authorized
    var isCalendarAuthorized: Bool {
        let status = calendarAuthorizationStatus
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        } else {
            return status == .authorized
        }
    }

    /// Create a calendar event with the given details
    /// - Parameters:
    ///   - title: The title of the event
    ///   - startDate: When the event starts
    ///   - endDate: When the event ends (defaults to 1 hour after start)
    ///   - notes: Optional notes for the event
    /// - Returns: The identifier of the created event
    func createCalendarEvent(
        title: String,
        startDate: Date,
        endDate: Date? = nil,
        notes: String? = nil
    ) async throws -> String {
        // Ensure we have access
        if !isCalendarAuthorized {
            let granted = try await requestCalendarAccess()
            guard granted else {
                throw ReminderServiceError.accessDenied
            }
        }

        // Get the default calendar
        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            throw ReminderServiceError.noDefaultCalendar
        }

        // Create the event
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.notes = notes
        event.calendar = calendar
        event.startDate = startDate
        event.endDate = endDate ?? startDate.addingTimeInterval(3600) // Default 1 hour duration

        // Add an alarm 15 minutes before
        let alarm = EKAlarm(relativeOffset: -15 * 60)
        event.addAlarm(alarm)

        // Save the event
        try eventStore.save(event, span: .thisEvent)

        print("Created calendar event: \(title) at \(startDate)")
        return event.calendarItemIdentifier
    }

    // MARK: - Reminder Management

    /// Fetch all incomplete reminders
    func fetchIncompleteReminders() async throws -> [EKReminder] {
        guard isAuthorized else {
            throw ReminderServiceError.accessDenied
        }

        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: nil
        )

        return try await withCheckedThrowingContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    /// Complete a reminder
    func completeReminder(identifier: String) async throws {
        guard isAuthorized else {
            throw ReminderServiceError.accessDenied
        }

        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw ReminderServiceError.reminderNotFound
        }

        reminder.isCompleted = true
        try eventStore.save(reminder, commit: true)
    }

    /// Delete a reminder
    func deleteReminder(identifier: String) async throws {
        guard isAuthorized else {
            throw ReminderServiceError.accessDenied
        }

        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw ReminderServiceError.reminderNotFound
        }

        try eventStore.remove(reminder, commit: true)
    }
}

// MARK: - Errors

enum ReminderServiceError: LocalizedError {
    case accessDenied
    case noDefaultCalendar
    case reminderNotFound
    case eventNotFound
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return L("Permission to access Reminders was denied. Please enable it in System Settings.")
        case .noDefaultCalendar:
            return L("No default calendar found for reminders.")
        case .reminderNotFound:
            return L("The reminder could not be found.")
        case .eventNotFound:
            return L("The event could not be found.")
        case .saveFailed:
            return L("Failed to save the reminder.")
        }
    }
}
