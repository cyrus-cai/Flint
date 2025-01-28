//
//  OnboardingView.swift
//  HyperNote
//
//  Created by LC John on 1/17/25.
//

import Foundation
import SwiftUI

struct OnboardingView: View {
    @Binding var isFirstLaunch: Bool
    @State private var currentStep = 0
    @State private var slideDirection: SlideDirection = .right
    @State private var isHoveredPrev = false

    enum SlideDirection {
        case left
        case right
    }

    private let steps = [
        OnboardingStep(
            icon: "bolt",
            title: "Designed for quick write-down",
            description: "Anywhere, press ⌥ + C.",
            detail: "",
            imageName: "quick-wake-demo",
            showLoginOption: true
        ),
        //        OnboardingStep(
        //            icon: "lock",
        //            title: "Local and private",
        //            description: "All your notes are stored locally",
        //            detail: "",
        //            hasAction: true,
        //            imageName: "local-private-demo"
        //        ),
        OnboardingStep(
            icon: "folder.badge.gearshape",
            title: "Where to save?",
            description: "Choose your folder",
            detail: "All your notes are stored locally",
            hasAction: true,
            imageName: "storage-config-demo"
        ),
        OnboardingStep(
            icon: "brain.head.profile",
            title: "AI, truly helpful",
            description: "Help summarize & make plans.",
            detail: "",
            hasAction: true,
            imageName: "local-private-demo"
        ),
        OnboardingStep(
            icon: "star",
            title: "Get Pro",
            description: "Get more with HyperNote Pro",
            detail: "",
            imageName: "pro-features-demo"
        ),
        OnboardingStep(
            icon: "checkmark.circle",
            title: "You're All Set!",
            description: "Ready to start your note-taking journey",
            detail: "",
            imageName: "getting-started-demo"
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator - 现在在顶部居中
            HStack {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.gray.opacity(0.15))
                            .frame(height: 8)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(.systemPurple), Color(.systemPink)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(
                                width: (CGFloat(currentStep + 1) / CGFloat(steps.count))
                                    * geometry.size.width,
                                height: 8
                            )
                    }
                }
                .frame(width: 48, height: 8)  // 缩小宽度和高度
                Spacer()
            }
            .padding(48)

            // Main content area
            HStack(spacing: 0) {
                // Left side - Content
                VStack {
                    // Content with slide animation
                    HStack(spacing: 0) {
                        ForEach(0..<steps.count, id: \.self) { index in
                            if index == currentStep {
                                StepContent(step: steps[index])
                                    .transition(
                                        .asymmetric(
                                            insertion: .offset(
                                                x: slideDirection == .right ? 100 : -100
                                            )
                                            .combined(with: .opacity)
                                            .combined(with: .scale(scale: 0.9)),
                                            removal: .offset(
                                                x: slideDirection == .right ? -100 : 100
                                            )
                                            .combined(with: .opacity)
                                            .combined(with: .scale(scale: 0.9))
                                        )
                                    )
                            }
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: currentStep)
                    .frame(maxWidth: .infinity)

                    Spacer()
                }
                .frame(width: 360)

                // Right side - Image/Video
                VStack {
                    if let imageName = steps[currentStep].imageName {
                        Image(imageName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 500, height: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
                            .offset(x: slideDirection == .right ? 30 : 30)
                            .animation(
                                .spring(response: 0.4, dampingFraction: 0.6), value: currentStep)
                    }
                }

            }
            .padding(48)

            // Navigation buttons
            HStack {
                if currentStep > 0 {
                    Button {
                        guard currentStep > 0 else { return }
                        slideDirection = .left
                        withAnimation {
                            currentStep -= 1
                        }
                    } label: {
                        Label("Previous", systemImage: "chevron.left")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                            .padding(8)
                            .background(
                                LinearGradient(
                                    colors: [.clear, .gray.opacity(0.08)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .cornerRadius(8)
                            )
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(isHoveredPrev ? 1.05 : 1)
                    .animation(.easeOut, value: isHoveredPrev)
                    .onHover { isHoveredPrev = $0 }
                }

                Spacer()

                // Show Skip and Configure Vault buttons only for the Select folder step
                if currentStep == 1 {  // Select folder step
                    Button("Skip") {
                        slideDirection = .right
                        withAnimation {
                            currentStep += 1
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)

                    Button("Configure Vault") {
                        let openPanel = NSOpenPanel()
                        openPanel.canChooseDirectories = true
                        openPanel.canChooseFiles = false
                        openPanel.allowsMultipleSelection = false
                        openPanel.title = "Select Notes Directory"

                        if openPanel.runModal() == .OK {
                            if let selectedPath = openPanel.url {
                                FileManager.shared.setCustomDirectory(selectedPath)
                                slideDirection = .right
                                withAnimation {
                                    currentStep += 1
                                }
                            }
                        }
                    }
                    .buttonStyle(GradientButtonStyle())
                    .controlSize(.large)
                } else if currentStep == 2 {  // Get Pro step
                    Button("Skip") {
                        slideDirection = .right
                        withAnimation {
                            currentStep += 1
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)

                    Button("Get Pro") {
                        if let url = URL(string: "https://google.com") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(GradientButtonStyle())
                    .controlSize(.large)
                } else {
                    // For other steps, show the regular Next/Start button
                    Button(currentStep == steps.count - 1 ? "Start HyperNote" : "Next Step") {
                        if currentStep == steps.count - 1 {
                            // Set hasCompletedOnboarding to true
                            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")

                            isFirstLaunch = false
                            if let window = NSApplication.shared.windows.first(where: {
                                $0.title == "Welcome to HyperNote"
                            }) {
                                window.close()
                            }
                            WindowManager.shared.createNewWindow()
                        } else {
                            slideDirection = .right
                            withAnimation {
                                currentStep += 1
                            }
                        }
                    }
                    .buttonStyle(GradientButtonStyle())
                    .controlSize(.large)
                }
            }
            .padding(48)
        }
    }
}

// Helper view to encapsulate step content
struct StepContent: View {
    let step: OnboardingStep
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    private let loginManager = LoginManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: step.icon)
                .font(.system(size: 40))
                .symbolEffect(.bounce.up, options: .speed(0.5).nonRepeating)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .pink],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            VStack(alignment: .leading, spacing: 8) {
                Text(step.title)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.primary, .primary.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Text(step.description)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)

                if !step.detail.isEmpty {
                    Text(step.detail)
                        .font(.system(size: 14))
                        .foregroundColor(.primary.opacity(0.8))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.primary.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.purple.opacity(0.1), lineWidth: 1)
                                )
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if step.showLoginOption {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Start at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { newValue in
                            if newValue {
                                loginManager.requestLaunchPermission { granted in
                                    if granted {
                                        loginManager.enableLaunchAtLogin()
                                    } else {
                                        DispatchQueue.main.async {
                                            launchAtLogin = false
                                        }
                                    }
                                }
                            } else {
                                loginManager.disableLaunchAtLogin()
                            }
                        }
                        .toggleStyle(.switch)
                        .padding(.top, 8)

                    Text("Quickly access HyperNote when you need it")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.primary.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.purple.opacity(0.1), lineWidth: 1)
                        )
                )
                .cornerRadius(12)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // .padding(.horizontal, 40)
        .padding(.vertical, 20)
    }
}

struct OnboardingStep {
    let icon: String
    let title: String
    let description: String
    let detail: String
    var hasAction: Bool = false
    var imageName: String?
    var showLoginOption: Bool = false
}

private struct GradientButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [Color(.systemPurple), Color(.systemPink)],
                    startPoint: isHovered ? .topLeading : .leading,
                    endPoint: isHovered ? .bottomTrailing : .trailing
                )
                .cornerRadius(10)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.4), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ), lineWidth: 1.5)
                )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : isHovered ? 1.04 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}
