//
//  OnboardingView.swift
//  Flint
//
//  Created by LC John on 1/17/25.
//

import AppKit
import ApplicationServices
import Foundation
import SwiftUI
import UserNotifications

struct OnboardingView: View {
    @Binding var isFirstLaunch: Bool
    @State private var page: OnboardingPage = .welcome
    @State private var storagePath = LocalFileManager.shared.currentNotesPath
    @StateObject private var permissionState = PermissionState()
    @Environment(\.colorScheme) private var colorScheme
    @State private var welcomeLogoAppeared = false
    @State private var controlKeyMonitor: Any?
    @State private var controlPressCount = 0
    @State private var lastControlPressDate: Date?
    @State private var controlFlash = false
    @AppStorage(AppStorageKeys.enableDoubleOption) private var enableDoubleControl = AppDefaults.enableDoubleOption

    private var pages: [OnboardingPage] { OnboardingPage.allCases }

    private var canMoveNext: Bool {
        switch page {
        case .welcome: return true
        case .wake: return true
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
            enableDoubleControl = true
            startControlKeyMonitor()
        }
        .onDisappear {
            stopControlKeyMonitor()
        }
        .onChange(of: page) { _, newPage in
            handlePageChange(newPage)
        }
        .onReceive(NotificationCenter.default.publisher(for: .storageLocationDidChange)) { _ in
            storagePath = LocalFileManager.shared.currentNotesPath
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionState.refresh()
        }
    }

    // MARK: - Welcome (Centered)

    private var welcomeContent: some View {
        Image(colorScheme == .dark ? "brand-name-icon-dark" : "brand-name-icon")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: 80)
            .opacity(welcomeLogoAppeared ? 1 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: 0.8)) {
                    welcomeLogoAppeared = true
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
            EmptyView()
        case .storage:
            StoragePage(storagePath: storagePath)
        case .permissions:
            PermissionsPage(state: permissionState)
        case .done:
            DonePage(onFinish: finishOnboarding)
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
        HStack(alignment: .bottom) {
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
                EmptyView()
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
                controlHintLabel
            }
        }
    }

    private var controlHintLabel: some View {
        VStack(alignment: .trailing, spacing: 6) {
            // Mac-style keycap: ⌃ top-right, control bottom-left
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(controlFlash
                        ? Color.accentColor.opacity(0.18)
                        : Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(controlFlash
                                ? Color.accentColor.opacity(0.35)
                                : Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 1, y: 1)

                Text("⌘")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(controlFlash ? .accentColor : .primary.opacity(0.55))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 8)
                    .padding(.trailing, 10)

                Text("command")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(controlFlash ? .accentColor : .primary.opacity(0.55))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.bottom, 8)
                    .padding(.leading, 10)
            }
            .frame(width: 80, height: 80)
            .scaleEffect(controlFlash ? 0.92 : 1)
            .animation(.easeOut(duration: 0.1), value: controlFlash)

            // Caption below keycap, right-aligned with keycap
            Text(page == .wake ? "× 2" : "Press to continue")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .opacity(canMoveNext ? 1 : 0.35)
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
        if newPage == .permissions {
            permissionState.refresh()
        }
        controlPressCount = 0
    }

    private func moveNext() {
        guard canMoveNext else { return }
        guard let index = pages.firstIndex(of: page), index < pages.count - 1 else { return }
        page = pages[index + 1]
    }

    // MARK: - Control Key Monitor

    private func startControlKeyMonitor() {
        controlKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            // Only react to pure Control (no Cmd/Option/Shift)
            let onlyControl = event.modifierFlags.contains(.command)
                && !event.modifierFlags.contains(.control)
                && !event.modifierFlags.contains(.option)
                && !event.modifierFlags.contains(.shift)

            guard onlyControl else { return event }

            // Skip pages that shouldn't advance via Control
            guard page != .storage, page != .done else { return event }

            // Visual flash feedback
            controlFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                controlFlash = false
            }

            let now = Date()

            if page == .wake {
                // Double-tap Control (within 0.3s) to advance
                if let last = lastControlPressDate, now.timeIntervalSince(last) < 0.3 {
                    controlPressCount += 1
                    lastControlPressDate = nil
                    moveNext()
                } else {
                    controlPressCount += 1
                    lastControlPressDate = now
                }
            } else {
                // Single press to advance
                controlPressCount += 1
                if canMoveNext {
                    moveNext()
                }
            }

            return event
        }
    }

    private func stopControlKeyMonitor() {
        if let monitor = controlKeyMonitor {
            NSEvent.removeMonitor(monitor)
            controlKeyMonitor = nil
        }
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
            return L("Double Press Command")
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
            return L("This is how you summon Flint. Try it now.")
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
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            tipRow(badge: "Ctrl Ctrl", text: L("to write something down"))
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
                    Text(L("Enabled"))
                        .font(.system(size: 13, weight: .medium))
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
