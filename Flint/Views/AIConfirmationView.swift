//
//  AIConfirmationView.swift
//  Flint
//
//  Created by AI Agent on 1/22/26.
//

import SwiftUI

/// A confirmation dialog for AI agent actions
struct AIConfirmationView: View {
    let intentResponse: IntentResponse
    let onConfirm: (Date?) -> Void
    let onCancel: () -> Void
    
    @State private var selectedDate: Date
    
    init(intentResponse: IntentResponse, onConfirm: @escaping (Date?) -> Void, onCancel: @escaping () -> Void) {
        self.intentResponse = intentResponse
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _selectedDate = State(initialValue: intentResponse.parsedDateTime?.date ?? Date())
    }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            headerSection

            Divider()
                .opacity(0.5)

            // Intent Details
            intentDetailsSection

            Divider()
                .opacity(0.5)

            // Action Buttons
            actionButtonsSection
        }
        .padding(20)
        .frame(width: 320)
        .modifier(AIConfirmationBackgroundModifier())
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: intentResponse.intent.iconName)
                .font(.system(size: 24, weight: .regular))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(.title3)
                    .fontWeight(.bold)
            }

            Spacer()
        }
    }

    private var headerTitle: String {
        switch intentResponse.intent {
        case .scheduleReminder:
            return L("Create Reminder")
        case .createCalendarEvent:
            return L("Create Event")
        case .textEditing:
            return L("Edit Text")
        case .quickNote:
            return L("Quick Note")
        case .unknown:
            return L("AI Agent")
        }
    }

    // Removed intentGradient


    // MARK: - Intent Details Section

    private var intentDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            if let title = intentResponse.title, !title.isEmpty {
                detailRow(
                    icon: "text.quote",
                    label: L("Title"),
                    value: title
                )
            }

            // Date/Time
            if intentResponse.parsedDateTime != nil {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundColor(.secondary)
                        .frame(width: 20)

                    Text(L("Time"))
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .leading)

                    DatePicker("", selection: $selectedDate, displayedComponents: [.date])
                        .labelsHidden()
                        .fixedSize()
                    
                    DatePicker("", selection: $selectedDate, displayedComponents: [.hourAndMinute])
                        .labelsHidden()
                        .fixedSize()
                        
                    Spacer()
                }
                .font(.callout)
            }

            // Confidence
            confidenceRow
        }
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 20)

            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .leading)

            Text(value)
                .foregroundColor(.primary)
                .lineLimit(2)

            Spacer()
        }
        .font(.callout)
    }

    private var confidenceRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .foregroundColor(.secondary)
                .frame(width: 20)

            Text(L("Confidence"))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .leading)

            Text(confidenceText)
                .fontWeight(.medium)
                .foregroundColor(confidenceColor)

            Spacer()
        }
        .font(.callout)
    }

    private var confidenceText: String {
        if intentResponse.confidence >= 0.8 {
            return L("High")
        } else if intentResponse.confidence >= 0.5 {
            return L("Medium")
        } else {
            return L("Low")
        }
    }

    private var confidenceColor: Color {
        if intentResponse.confidence >= 0.8 {
            return .green
        } else if intentResponse.confidence >= 0.5 {
            return .orange
        } else {
            return .red
        }
    }

    // MARK: - Action Buttons Section

    private var actionButtonsSection: some View {
        HStack(spacing: 12) {
            // Cancel Button
            Button(role: .cancel, action: onCancel) {
                Text(L("Cancel"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            // Confirm Button
            Button(action: {
                if intentResponse.hasTimeInfo {
                    onConfirm(selectedDate)
                } else {
                    onConfirm(nil)
                }
            }) {
                HStack(spacing: 6) {
                    Text(confirmButtonText)
                    Image(systemName: "checkmark")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var confirmButtonText: String {
        switch intentResponse.intent {
        case .scheduleReminder:
            return L("Create Reminder")
        case .createCalendarEvent:
            return L("Create Event")
        default:
            return L("Confirm")
        }
    }
}

// MARK: - Background Modifier

private struct AIConfirmationBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            // macOS 26+: Use native Liquid Glass effect
            content
                .glassEffect(in: .rect(cornerRadius: 16))
        } else {
            // macOS 15-25: Use traditional background
            content
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(colorScheme == .dark ? Color(NSColor.windowBackgroundColor) : Color.white)
                        .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
        }
    }
}

// MARK: - AI Processing Indicator

struct AIProcessingIndicator: View {
    @State private var animationProgress: CGFloat = 0
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        HStack(spacing: 10) {
            // Animated ring
            ZStack {
                if #available(macOS 26.0, *) {
                    // macOS 26+ Native AI Gradient Ring
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.2, green: 0.6, blue: 1.0),
                            Color(red: 0.8, green: 0.2, blue: 0.8),
                            Color(red: 1.0, green: 0.4, blue: 0.2),
                            Color(red: 0.2, green: 0.6, blue: 1.0)
                        ]),
                        center: .center
                    )
                    .mask(
                        Circle()
                            .stroke(lineWidth: 2.5)
                    )
                    .frame(width: 20, height: 20)
                    .rotationEffect(Angle(degrees: animationProgress * 360))
                    .blur(radius: 0.5)
                } else {
                    // Fallback for older macOS
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.purple, .blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 20, height: 20)
                        .rotationEffect(Angle(degrees: animationProgress * 360))
                }
            }
            .scaleEffect(pulseScale)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    animationProgress = 1.0
                }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulseScale = 1.1
                }
            }

            Text(L("AI Processing..."))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .modifier(AIProcessingBackgroundModifier())
    }
}

private struct AIProcessingBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(in: .capsule)
        } else {
            content
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                )
        }
    }
}

// MARK: - Preview

//#Preview {
//    let mockResponse = IntentResponse(
//        intent: .scheduleReminder,
//        title: "Team Meeting",
//        parsedDateTime: ParsedDateTime(
//            date: Date().addingTimeInterval(86400),
//            isAllDay: false,
//            confidence: 0.95,
//            originalText: "tomorrow 3pm"
//        ),
//        notes: nil,
//        confidence: 0.92,
//        suggestions: ["Add meeting location", "Set 15-minute early reminder"],
//        rawInterpretation: "I understand you want to be reminded about 'Team Meeting' tomorrow at 3:00 PM"
//    )
//
//    AIConfirmationView(
//        intentResponse: mockResponse,
//        onConfirm: { date in print("Confirmed with date: \(String(describing: date))") },
//        onCancel: { print("Cancelled") }
//    )
//    .padding()
//}
