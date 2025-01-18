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
    
    var body: some View {
        VStack(spacing: 30) {
            // Header
            VStack(spacing: 16) {
                Image(systemName: "note.text")
                    .font(.system(size: 60))
                    .foregroundColor(.purple)
                
                Text("Welcome to HyperNote")
                    .font(.title)
                    .bold()
                
                Text("Your quick capture companion")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Features
            VStack(alignment: .leading, spacing: 20) {
                FeatureRow(
                    icon: "bolt",
                    title: "Quick Wake-up",
                    description: "Press ⌥ + C to quickly capture your thoughts"
                )
                
                FeatureRow(
                    icon: "clock",
                    title: "History Access",
                    description: "Press ⌘ + H to access your note history"
                )
                
                FeatureRow(
                    icon: "link",
                    title: "Smart Links",
                    description: "Automatically detects and manages your links"
                )
            }
            .padding(.horizontal)
            
            // Get Started Button
            Button("Get Started") {
                withAnimation {
                    isFirstLaunch = false
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .controlSize(.large)
        }
        .padding(40)
        .frame(width: 480)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.purple)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}
