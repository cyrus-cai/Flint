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

    private let steps = [
        OnboardingStep(
            icon: "bolt",
            title: "Quick Wake-up",
            description: "Press ⌥ + C to quickly capture your thoughts",
            detail: ""
        ),
        OnboardingStep(
            icon: "paperplane",
            title: "Quick Publish",
            description: "Press ⌘ + Enter or ⌘ + K to publish your note",
            detail: ""
        ),
        OnboardingStep(
            icon: "folder.badge.gearshape",
            title: "Configure Storage",
            description: "Set up your Obsidian vault location",
            detail: "",
            hasAction: true
        ),
        OnboardingStep(
            icon: "star",
            title: "Unlock Pro Features",
            description: "Get more with HyperNote Pro",
            detail: ""
        ),
        OnboardingStep(
            icon: "checkmark.circle",
            title: "You're All Set!",
            description: "Ready to start your note-taking journey",
            detail: ""
        ),
    ]

    var body: some View {
        VStack(spacing: 30) {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(0..<steps.count, id: \.self) { index in
                    Circle()
                        .fill(index <= currentStep ? Color.purple : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top)

            // Content
            VStack(spacing: 16) {
                Image(systemName: steps[currentStep].icon)
                    .font(.system(size: 60))
                    .foregroundColor(.purple)

                Text(steps[currentStep].title)
                    .font(.title)
                    .bold()

                Text(steps[currentStep].description)
                    .font(.title3)
                    .foregroundColor(.secondary)

                Text(steps[currentStep].detail)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if steps[currentStep].hasAction {
                Button("Configure Vault") {
                    WindowManager.shared.createSettingsWindow()
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            }

            Spacer()

            // Navigation buttons
            HStack {
                if currentStep > 0 {
                    Button("Previous") {
                        withAnimation {
                            currentStep -= 1
                        }
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button(currentStep == steps.count - 1 ? "Start HyperNote" : "Next Step") {
                    withAnimation {
                        if currentStep == steps.count - 1 {
                            isFirstLaunch = false
                            if let window = NSApplication.shared.windows.first(where: {
                                $0.title == "Welcome to HyperNote"
                            }) {
                                window.close()
                            }
                            WindowManager.shared.createNewWindow()
                        } else {
                            currentStep += 1
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .controlSize(.large)
            }
        }
        .padding(40)
        .frame(width: 480)
    }
}

struct OnboardingStep {
    let icon: String
    let title: String
    let description: String
    let detail: String
    var hasAction: Bool = false
}
