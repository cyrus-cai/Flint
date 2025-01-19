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

    enum SlideDirection {
        case left
        case right
    }

    private let steps = [
        OnboardingStep(
            icon: "bolt",
            title: "Quick Wake-up",
            description: "Press ⌥ + C to quickly capture your thoughts",
            detail: "",
            imageName: "quick-wake-demo"
        ),
        OnboardingStep(
            icon: "paperplane",
            title: "Quick Publish",
            description: "Press ⌘ + Enter or ⌘ + K to publish your note",
            detail: "",
            imageName: "quick-publish-demo"
        ),
        OnboardingStep(
            icon: "folder.badge.gearshape",
            title: "Configure Storage",
            description: "Set up your Obsidian vault location",
            detail: "",
            hasAction: true,
            imageName: "storage-config-demo"
        ),
        OnboardingStep(
            icon: "star",
            title: "Unlock Pro Features",
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
            HStack(spacing: 6) {
                ForEach(0..<steps.count, id: \.self) { index in
                    Circle()
                        .fill(index <= currentStep ? Color.purple : Color.gray.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.top, 8)

            // Main content area
            HStack(spacing: 0) {
                // Left side - Content
                VStack(spacing: 30) {
                    // Content with slide animation
                    HStack(spacing: 0) {
                        ForEach(0..<steps.count, id: \.self) { index in
                            if index == currentStep {
                                StepContent(step: steps[index])
                                    .transition(
                                        .asymmetric(
                                            insertion: .move(
                                                edge: slideDirection == .right
                                                    ? .trailing : .leading),
                                            removal: .move(
                                                edge: slideDirection == .right
                                                    ? .leading : .trailing)
                                        ))
                            }
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: currentStep)
                    .frame(maxWidth: .infinity)

                    // Action button (Configure Vault)
                    if steps[currentStep].hasAction {
                        Button("Configure Vault") {
                            WindowManager.shared.createSettingsWindow()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                    }

                    Spacer()
                }
                .padding(40)
                .frame(width: 480)

                // Right side - Image/Video
                VStack {
                    if let imageName = steps[currentStep].imageName {
                        Image(imageName)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 440, height: 320)
                            .clipped()

                            .transition(.opacity)
                    }
                }
                .padding(40)
                .background(Color(.windowBackgroundColor))
            }

            // Navigation buttons - 现在在底部，跨越整个宽度
            HStack {
                if currentStep > 0 {
                    Button("Previous") {
                        slideDirection = .left
                        withAnimation {
                            currentStep -= 1
                        }
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button(currentStep == steps.count - 1 ? "Start HyperNote" : "Next Step") {
                    if currentStep == steps.count - 1 {
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
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .controlSize(.large)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }
}

// Helper view to encapsulate step content
struct StepContent: View {
    let step: OnboardingStep

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: step.icon)
                .font(.system(size: 60))
                .foregroundColor(.purple)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(step.title)
                .font(.title)
                .bold()
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(step.description)
                .font(.title3)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(step.detail)
                .font(.body)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OnboardingStep {
    let icon: String
    let title: String
    let description: String
    let detail: String
    var hasAction: Bool = false
    var imageName: String?
}
