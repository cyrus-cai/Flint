//
//  OnboardingView.swift
//  Flint
//
//  Created by LC John on 1/17/25.
//

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import KeyboardShortcuts
import SwiftUI
import UserNotifications

struct OnboardingView: View {
    @Binding var isFirstLaunch: Bool
    @State private var page: OnboardingPage = .wake
    @State private var storagePath = LocalFileManager.shared.currentNotesPath
    @StateObject private var shortcutState = ShortcutCaptureState()
    @StateObject private var permissionState = PermissionState()
    @Environment(\.colorScheme) private var colorScheme

    private var pages: [OnboardingPage] { OnboardingPage.allCases }
    private var canMoveNext: Bool { page != .wake || shortcutState.hasShortcut }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 24) {
                    Text(page.title)
                        .font(.system(size: 32, weight: .semibold))

                    pageContent
                        .frame(maxWidth: 640)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
                .animation(.easeInOut(duration: 0.18), value: page)

                Spacer(minLength: 0)

                footer
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            handlePageChange(page)
            permissionState.refresh()
        }
        .onChange(of: page) { _, newPage in
            handlePageChange(newPage)
        }
        .onReceive(NotificationCenter.default.publisher(for: .storageLocationDidChange)) { _ in
            storagePath = LocalFileManager.shared.currentNotesPath
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionState.refresh()
            shortcutState.sync()
        }
        .onChange(of: shortcutState.didAccept) { _, accepted in
            if accepted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    moveNext()
                }
            }
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .wake:
            WakePage(state: shortcutState)
        case .storage:
            StoragePage(storagePath: storagePath, onChangeLocation: selectCustomDirectory)
        case .permissions:
            PermissionsPage(state: permissionState)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                moveBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(page == pages.first ? .clear : .secondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(page == pages.first)

            Spacer()

            HStack(spacing: 8) {
                ForEach(pages) { item in
                    Capsule()
                        .fill(item == page ? Color.accentColor.opacity(0.88) : Color.primary.opacity(0.12))
                        .frame(width: item == page ? 20 : 8, height: 8)
                }
            }

            Spacer()

            if page == .permissions {
                Button(L("New Note")) {
                    finishOnboarding()
                }
                .buttonStyle(MinimalPrimaryButtonStyle())
            } else {
                Button {
                    moveNext()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(MinimalIconButtonStyle())
                .disabled(!canMoveNext)
                .opacity(canMoveNext ? 1 : 0.35)
            }
        }
    }

    private var background: some View {
        ZStack {
            GlassBackdrop()

            Circle()
                .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.08 : 0.06))
                .frame(width: 300, height: 300)
                .blur(radius: 110)
                .offset(x: 220, y: -160)

            Circle()
                .fill(Color(red: 0.87, green: 0.70, blue: 0.48).opacity(colorScheme == .dark ? 0.05 : 0.06))
                .frame(width: 240, height: 240)
                .blur(radius: 100)
                .offset(x: -220, y: 180)

            Rectangle()
                .fill(
                    colorScheme == .dark
                        ? Color.black.opacity(0.14)
                        : Color.white.opacity(0.18)
                )
        }
        .ignoresSafeArea()
    }

    private func handlePageChange(_ newPage: OnboardingPage) {
        if newPage == .wake {
            shortcutState.activateIfNeeded()
        } else {
            shortcutState.stopRecording(restoreDisplay: true)
        }

        if newPage == .permissions {
            permissionState.refresh()
        }
    }

    private func moveNext() {
        guard canMoveNext else { return }
        guard let index = pages.firstIndex(of: page), index < pages.count - 1 else { return }

        // When leaving the storage page, open NSOpenPanel so the system grants
        // folder-access permission right away (instead of prompting later).
        if page == .storage {
            let openPanel = NSOpenPanel()
            openPanel.canChooseDirectories = true
            openPanel.canChooseFiles = false
            openPanel.allowsMultipleSelection = false
            openPanel.title = L("Select Notes Directory")
            openPanel.directoryURL = URL(fileURLWithPath: storagePath)

            guard openPanel.runModal() == .OK, let selectedURL = openPanel.url else { return }
            LocalFileManager.shared.setCustomDirectory(selectedURL)
            storagePath = LocalFileManager.shared.currentNotesPath
        }

        page = pages[index + 1]
    }

    private func moveBack() {
        guard let index = pages.firstIndex(of: page), index > 0 else { return }
        page = pages[index - 1]
    }

    private func selectCustomDirectory() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.allowsMultipleSelection = false
        openPanel.title = L("Select Notes Directory")

        if openPanel.runModal() == .OK, let selectedPath = openPanel.url {
            LocalFileManager.shared.setCustomDirectory(selectedPath)
            storagePath = LocalFileManager.shared.currentNotesPath
        }
    }

    private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        isFirstLaunch = false
        WindowManager.shared.dismissOnboarding()
        WindowManager.shared.createNewWindow()
    }
}

private enum OnboardingPage: Int, CaseIterable, Identifiable {
    case wake
    case storage
    case permissions

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .wake:
            return L("Press Two Keys")
        case .storage:
            return L("Save Here")
        case .permissions:
            return L("Open Permissions")
        }
    }
}

private struct WakePage: View {
    @ObservedObject var state: ShortcutCaptureState

    var body: some View {
        Button {
            state.startRecording()
        } label: {
            HStack(spacing: 20) {
                ShortcutKeyCap(
                    text: state.modifierText,
                    isRecording: state.isRecording,
                    isFilled: !state.modifierText.isEmpty
                )

                ShortcutKeyCap(
                    text: state.keyText,
                    isRecording: state.isRecording,
                    isFilled: !state.keyText.isEmpty
                )
            }
            .overlay(alignment: .topTrailing) {
                if state.didAccept {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .background(Circle().fill(Color.noteWindowBackground))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: state.didAccept)
        }
        .buttonStyle(.plain)
    }
}

private struct StoragePage: View {
    let storagePath: String
    let onChangeLocation: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "folder.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.accentColor.opacity(0.10))
                )

            Text(storagePath)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 12)

            Button {
                onChangeLocation()
            } label: {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(MinimalIconButtonStyle())
        }
        .padding(18)
        .modifier(GlassCardModifier(cornerRadius: 20))
    }
}

private struct PermissionsPage: View {
    @ObservedObject var state: PermissionState

    var body: some View {
        VStack(spacing: 12) {
            PermissionRow(
                title: L("Accessibility"),
                isEnabled: state.accessibilityEnabled,
                action: state.requestAccessibility
            )

            PermissionRow(
                title: L("Notifications"),
                isEnabled: state.notificationsEnabled,
                action: state.requestNotifications
            )
        }
    }
}

@MainActor
private final class ShortcutCaptureState: ObservableObject {
    @Published private(set) var shownShortcut: KeyboardShortcuts.Shortcut?
    @Published private(set) var isRecording = false
    @Published var didAccept = false

    private var eventMonitor: Any?

    var hasShortcut: Bool { shownShortcut != nil }

    var modifierText: String {
        guard let shortcut = shownShortcut else { return "" }
        return shortcut.modifiers.displayText
    }

    var keyText: String {
        guard let shortcut = shownShortcut else { return "" }
        let whole = shortcut.description
        let modifiers = shortcut.modifiers.displayText
        guard !modifiers.isEmpty, whole.hasPrefix(modifiers) else { return whole }
        return String(whole.dropFirst(modifiers.count))
    }

    init() {
        shownShortcut = KeyboardShortcuts.getShortcut(for: .quickWakeup)
    }

    func sync() {
        if !isRecording {
            shownShortcut = KeyboardShortcuts.getShortcut(for: .quickWakeup)
        }
    }

    func activateIfNeeded() {
        sync()

        if shownShortcut == nil {
            startRecording()
        }
    }

    func startRecording() {
        stopRecording(restoreDisplay: false)
        shownShortcut = nil
        isRecording = true

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func stopRecording(restoreDisplay: Bool) {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }

        isRecording = false

        if restoreDisplay {
            shownShortcut = KeyboardShortcuts.getShortcut(for: .quickWakeup)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard isRecording else { return event }

        if event.modifierFlags.isEmpty, event.keyCode == kVK_Escape {
            stopRecording(restoreDisplay: true)
            return nil
        }

        guard
            let shortcut = KeyboardShortcuts.Shortcut(event: event),
            shortcut.modifiers.subtracting([.shift, .function]).isEmpty == false
        else {
            NSSound.beep()
            return nil
        }

        KeyboardShortcuts.setShortcut(shortcut, for: .quickWakeup)
        shownShortcut = shortcut
        stopRecording(restoreDisplay: false)
        didAccept = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            Task { @MainActor in
                self?.didAccept = false
            }
        }

        return nil
    }
}

@MainActor
private final class PermissionState: ObservableObject {
    @Published private(set) var accessibilityEnabled = AXIsProcessTrusted()
    @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined

    var notificationsEnabled: Bool {
        notificationStatus == .authorized || notificationStatus == .provisional
    }

    func refresh() {
        accessibilityEnabled = AXIsProcessTrusted()

        Task {
            let status = await NotificationService.shared.checkAuthorizationStatus()
            await MainActor.run {
                self.notificationStatus = status
            }
        }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refresh()
    }

    func requestNotifications() {
        Task {
            if notificationStatus == .denied {
                openNotificationSettings()
                return
            }

            _ = try? await NotificationService.shared.requestAuthorization()
            await MainActor.run {
                self.refresh()
            }
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}

private struct ShortcutKeyCap: View {
    let text: String
    let isRecording: Bool
    let isFilled: Bool

    var body: some View {
        Color.clear
            .frame(width: 180, height: 180)
            .modifier(GlassCardModifier(cornerRadius: 28, shadowOpacity: 0.06))
            .overlay {
                RoundedRectangle(cornerRadius: 28)
                    .stroke(strokeColor, lineWidth: isRecording || isFilled ? 1.5 : 1)
            }
            .overlay {
                Text(text)
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary.opacity(isFilled ? 0.88 : 0))
            }
    }

    private var strokeColor: Color {
        if isRecording {
            return Color.accentColor.opacity(0.48)
        }

        if isFilled {
            return Color.accentColor.opacity(0.20)
        }

        return Color.primary.opacity(0.08)
    }
}

private struct PermissionRow: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.system(size: 15, weight: .medium))

            Spacer()

            if isEnabled {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.accentColor)
            } else {
                Button(L("Enable")) {
                    action()
                }
                .buttonStyle(MinimalSecondaryButtonStyle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .modifier(GlassCardModifier(cornerRadius: 18))
    }
}

private struct MinimalPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.72 : 0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct MinimalIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.accentColor)
            .frame(width: 38, height: 38)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.14 : 0.08))
            )
            .modifier(GlassCardModifier(cornerRadius: 12, shadowOpacity: 0))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct MinimalSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.accentColor)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(
                Capsule()
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.14 : 0.08))
            )
            .modifier(CapsuleGlassModifier(shadowOpacity: 0))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct GlassBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                Rectangle()
                    .fill(Color.clear)
                    .glassEffect(in: .rect(cornerRadius: 0))
            } else {
                VisualEffectBlur(
                    material: .hudWindow,
                    blendingMode: .behindWindow,
                    state: .active
                )
            }
        }
        .overlay(
            colorScheme == .dark
                ? Color.black.opacity(0.10)
                : Color.white.opacity(0.10)
        )
    }
}

private struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    var shadowOpacity: Double = 0.08

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.clear)
                        .glassEffect(in: .rect(cornerRadius: cornerRadius))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: .black.opacity(shadowOpacity), radius: 18, x: 0, y: 10)
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.regularMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: .black.opacity(shadowOpacity), radius: 18, x: 0, y: 10)
        }
    }
}

private struct CapsuleGlassModifier: ViewModifier {
    var shadowOpacity: Double = 0.06

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .background(
                    Capsule()
                        .fill(Color.clear)
                        .glassEffect(in: .capsule)
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: .black.opacity(shadowOpacity), radius: 14, x: 0, y: 8)
        } else {
            content
                .background(Capsule().fill(.thinMaterial))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: .black.opacity(shadowOpacity), radius: 14, x: 0, y: 8)
        }
    }
}

private extension NSEvent.ModifierFlags {
    var displayText: String {
        var value = ""

        if contains(.control) {
            value += "⌃"
        }

        if contains(.option) {
            value += "⌥"
        }

        if contains(.shift) {
            value += "⇧"
        }

        if contains(.command) {
            value += "⌘"
        }

        return value
    }
}
