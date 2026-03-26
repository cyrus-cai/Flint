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
    @State private var page: OnboardingPage = .welcome
    @State private var storagePath = LocalFileManager.shared.currentNotesPath
    @StateObject private var shortcutState = ShortcutCaptureState()
    @StateObject private var permissionState = PermissionState()
    @Environment(\.colorScheme) private var colorScheme
    @State private var welcomeLogoAppeared = false
    @State private var welcomeTextAppeared = false
    @AppStorage(AppStorageKeys.enableDoubleOption) private var enableDoubleControl = AppDefaults.enableDoubleOption

    private var pages: [OnboardingPage] { OnboardingPage.allCases }

    private var canMoveNext: Bool {
        switch page {
        case .welcome: return true
        case .wake: return shortcutState.hasShortcut
        case .storage: return true
        case .permissions: return true
        case .done: return false
        }
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                progressBar
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                    .padding(.horizontal, 28)

                Spacer(minLength: 0)

                Group {
                    if page == .welcome {
                        welcomeContent
                    } else {
                        splitContent
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .animation(.easeInOut(duration: 0.18), value: page)

                Spacer(minLength: 0)

                footer
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
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

    // MARK: - Welcome (Centered)

    private var welcomeContent: some View {
        VStack(spacing: 28) {
            Image(colorScheme == .dark ? "brand-name-icon-dark" : "brand-name-icon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 80)
                .scaleEffect(welcomeLogoAppeared ? 1 : 1.2)
                .opacity(welcomeLogoAppeared ? 1 : 0)

            Text(L("Flint lives in the background until you need it."))
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
                .opacity(welcomeTextAppeared ? 1 : 0)
                .offset(y: welcomeTextAppeared ? 0 : 8)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                welcomeLogoAppeared = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeOut(duration: 0.6)) {
                    welcomeTextAppeared = true
                }
            }
        }
    }

    // MARK: - Split Layout (Pages 2–5)

    private var splitContent: some View {
        HStack(spacing: 0) {
            leftColumn
                .frame(maxWidth: .infinity, alignment: .leading)

            rightColumn
                .frame(maxWidth: .infinity, maxHeight: 380)
        }
        .frame(maxWidth: 840)
    }

    @ViewBuilder
    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(page.title)
                .font(.custom("Georgia", size: 32).weight(.semibold))

            if let subtitle = page.subtitle {
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer().frame(height: 4)

            leftPageContent
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.trailing, 28)
    }

    @ViewBuilder
    private var leftPageContent: some View {
        switch page {
        case .welcome:
            EmptyView()
        case .wake:
            WakePage(state: shortcutState)
        case .storage:
            StoragePage(storagePath: storagePath)
        case .permissions:
            PermissionsPage(state: permissionState)
        case .done:
            DonePage(shortcutDescription: shortcutState.shownShortcut?.description ?? "", onFinish: finishOnboarding)
        }
    }

    @ViewBuilder
    private var rightColumn: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        let progress = CGFloat((page.rawValue)) / CGFloat(pages.count - 1)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Full bar — dim glass
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 6)

                // Progress portion — brighter glass overlay
                Capsule()
                    .fill(Color.primary.opacity(0.18))
                    .frame(width: max(6, geo.size.width * progress), height: 6)
            }
            .animation(.easeInOut(duration: 0.3), value: page)
        }
        .frame(width: 120, height: 6)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer

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

            if page == .done {
                Color.clear.frame(width: 36, height: 36)
            } else if page == .storage {
                Button {
                    grantFolderAccessAndAdvance()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text(L("Grant Folder Access"))
                    }
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

    // MARK: - Background

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

    // MARK: - Navigation

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
        page = pages[index + 1]
    }

    private func moveBack() {
        guard let index = pages.firstIndex(of: page), index > 0 else { return }
        page = pages[index - 1]
    }

    private func grantFolderAccessAndAdvance() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.allowsMultipleSelection = false
        openPanel.title = L("Select Notes Directory")
        openPanel.directoryURL = URL(fileURLWithPath: storagePath)

        guard openPanel.runModal() == .OK, let selectedURL = openPanel.url else { return }
        LocalFileManager.shared.setCustomDirectory(selectedURL)
        storagePath = LocalFileManager.shared.currentNotesPath
        moveNext()
    }

    private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        isFirstLaunch = false
        WindowManager.shared.dismissOnboarding()
        WindowManager.shared.createNewWindow()
    }
}

// MARK: - Page Enum

private enum OnboardingPage: Int, CaseIterable, Identifiable {
    case welcome
    case wake
    case storage
    case permissions
    case done

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome:
            return "Flint"
        case .wake:
            return L("Summon It")
        case .storage:
            return L("Your Files, Your Folder")
        case .permissions:
            return L("Almost There")
        case .done:
            return L("Ready")
        }
    }

    var subtitle: String? {
        switch self {
        case .welcome:
            return nil
        case .wake:
            return L("Pick a shortcut. Flint stays hidden until you call.")
        case .storage:
            return L("Every note is a plain text file. No account, no cloud.")
        case .permissions:
            return nil
        case .done:
            return nil
        }
    }
}

// MARK: - Page Content Views

private struct WakePage: View {
    @ObservedObject var state: ShortcutCaptureState
    @AppStorage(AppStorageKeys.enableDoubleOption) private var enableDoubleControl = AppDefaults.enableDoubleOption

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button {
                state.startRecording()
            } label: {
                HStack(spacing: 16) {
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
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.accentColor)
                            .background(Circle().fill(Color.noteWindowBackground))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.22, dampingFraction: 0.8), value: state.didAccept)
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Toggle("", isOn: $enableDoubleControl)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                Text(L("Enable Double press Control key"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            enableDoubleControl = true
        }
    }
}

private struct StoragePage: View {
    let storagePath: String

    var body: some View {
        HStack(spacing: 12) {
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
        }
    }
}

private struct PermissionsPage: View {
    @ObservedObject var state: PermissionState

    var body: some View {
        VStack(spacing: 12) {
            PermissionRow(
                title: L("Accessibility"),
                reason: L("So Flint can appear anywhere, anytime."),
                isEnabled: state.accessibilityEnabled,
                action: state.requestAccessibility
            )

            PermissionRow(
                title: L("Notifications"),
                reason: L("So you know when a note is saved."),
                isEnabled: state.notificationsEnabled,
                action: state.requestNotifications
            )
        }
    }
}

private struct DonePage: View {
    let shortcutDescription: String
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            tipRow(badge: shortcutDescription, text: L("to write something down"))
            tipRow(badge: "Ctrl Ctrl", text: L("to pick up where you left off"))
            tipRow(badge: "⌘C ⌘C", text: L("to capture from anywhere"))

            Spacer().frame(height: 12)

            Button(L("New Note")) {
                onFinish()
            }
            .buttonStyle(MinimalPrimaryButtonStyle())
        }
    }

    private func tipRow(badge: String, text: String) -> some View {
        HStack(spacing: 12) {
            Text(badge)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(minWidth: 72, alignment: .leading)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary.opacity(0.8))
        }
    }
}

// MARK: - Right Column Illustrations

private struct WakeIllustration: View {
    var body: some View {
        Image("quick-wake-demo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(20)
    }
}

private struct StorageIllustration: View {
    var body: some View {
        Image("local-private-demo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(20)
    }
}

private struct PermissionsIllustration: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.accentColor)

            HStack(spacing: 20) {
                VStack(spacing: 6) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.accentColor.opacity(0.7))
                    Text(L("Accessibility"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                VStack(spacing: 6) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.accentColor.opacity(0.7))
                    Text(L("Notifications"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

private struct DoneIllustration: View {
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 20) {
            Image(colorScheme == .dark ? "brand-name-icon-dark" : "brand-name-icon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 56)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.accentColor)
        }
    }
}

// MARK: - Shortcut Capture State

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

    private static let reservedKeys: Set<Int> = [
        kVK_ANSI_W, kVK_ANSI_Q, kVK_ANSI_H, kVK_ANSI_M,   // Cmd+W/Q/H/M
        kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_X, kVK_ANSI_A,   // Cmd+C/V/X/A
        kVK_ANSI_Z, kVK_ANSI_S, kVK_ANSI_N, kVK_ANSI_O,   // Cmd+Z/S/N/O
        kVK_ANSI_P, kVK_ANSI_F, kVK_Tab,                    // Cmd+P/F/Tab
    ].map { Int($0) }.reduce(into: Set<Int>()) { $0.insert($1) }

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

        // Block system-reserved shortcuts (Cmd+W, Cmd+Q, etc.)
        let onlyCmd = shortcut.modifiers.subtracting([.shift, .function]) == .command
        if onlyCmd && Self.reservedKeys.contains(Int(event.keyCode)) {
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

// MARK: - Permission State

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

// MARK: - Component Views

private struct ShortcutKeyCap: View {
    let text: String
    let isRecording: Bool
    let isFilled: Bool

    var body: some View {
        Color.clear
            .frame(width: 140, height: 140)
            .modifier(GlassCardModifier(cornerRadius: 24, shadowOpacity: 0.06))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(strokeColor, lineWidth: isRecording || isFilled ? 1.5 : 1)
            }
            .overlay {
                Text(text)
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
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
    let reason: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                Text(title)
                    .font(.custom("Georgia", size: 15).weight(.medium))

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

            Text(reason)
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.8))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .modifier(GlassCardModifier(cornerRadius: 18))
    }
}

// MARK: - Button Styles

private struct MinimalPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("Georgia", size: 14).weight(.semibold))
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
            .font(.custom("Georgia", size: 13).weight(.semibold))
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

// MARK: - Glass Effects

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

// MARK: - Helpers

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
