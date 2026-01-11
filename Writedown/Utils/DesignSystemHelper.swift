//
//  DesignSystemHelper.swift
//  Writedown
//
//  Created for macOS 26 Liquid Glass adaptation
//  Provides version detection and design system utilities
//

import AppKit
import SwiftUI

// MARK: - Design System Version Detection

/// Helper struct for detecting and adapting to different macOS design systems
struct DesignSystem {
    
    /// Returns true if the current system supports Liquid Glass (macOS 26+)
    static var supportsLiquidGlass: Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }
    
    /// Returns true if running on macOS 15 (Sequoia) or later
    static var isSequoiaOrLater: Bool {
        if #available(macOS 15.0, *) {
            return true
        }
        return false
    }
    
    /// The recommended corner radius for the current design system
    static var standardCornerRadius: CGFloat {
        if #available(macOS 26.0, *) {
            return 16 // Larger, softer corners for Liquid Glass
        }
        return 12 // Traditional macOS corner radius
    }
    
    /// The recommended small corner radius for buttons and controls
    static var smallCornerRadius: CGFloat {
        if #available(macOS 26.0, *) {
            return 10
        }
        return 8
    }
}

// MARK: - Adaptive Glass Background Modifier

/// A view modifier that applies appropriate background based on macOS version
struct AdaptiveGlassBackground: ViewModifier {
    var material: NSVisualEffectView.Material
    var cornerRadius: CGFloat?
    
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            // macOS 26+: Use new glass effect system
            // Note: The actual .glassEffect() API will be available in Xcode 26
            // For now, we use a placeholder that can be updated
            content
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius ?? DesignSystem.standardCornerRadius)
                        .fill(.ultraThinMaterial)
                }
        } else {
            // macOS 15-25: Use traditional NSVisualEffectView
            content
                .background(
                    LegacyVisualEffectView(material: material)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? DesignSystem.standardCornerRadius))
                )
        }
    }
}

// MARK: - View Extension

extension View {
    /// Applies an adaptive glass background that uses Liquid Glass on macOS 26+
    /// and falls back to NSVisualEffectView on older systems
    func adaptiveGlassBackground(
        material: NSVisualEffectView.Material = .sidebar,
        cornerRadius: CGFloat? = nil
    ) -> some View {
        modifier(AdaptiveGlassBackground(material: material, cornerRadius: cornerRadius))
    }
    
    /// Applies background only on macOS 26+ (Liquid Glass era)
    @ViewBuilder
    func liquidGlassOnly<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        if #available(macOS 26.0, *) {
            self.background(content())
        } else {
            self
        }
    }
    
    /// Applies background only on pre-macOS 26 systems
    @ViewBuilder
    func legacyOnly<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        if #available(macOS 26.0, *) {
            self
        } else {
            self.background(content())
        }
    }
}

// MARK: - Legacy Visual Effect View (for backward compatibility)

/// NSViewRepresentable wrapper for NSVisualEffectView (used on macOS 15-25)
struct LegacyVisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    var state: NSVisualEffectView.State = .active
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.wantsLayer = true
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

// MARK: - Adaptive Material Background

/// SwiftUI Material that adapts to macOS version
struct AdaptiveMaterial: View {
    var style: MaterialStyle
    
    enum MaterialStyle {
        case thin
        case regular
        case thick
        case sidebar
        case hudWindow
        
        var legacyMaterial: NSVisualEffectView.Material {
            switch self {
            case .thin: return .headerView
            case .regular: return .contentBackground
            case .thick: return .sidebar
            case .sidebar: return .sidebar
            case .hudWindow: return .hudWindow
            }
        }
        
        @available(macOS 15.0, *)
        var swiftUIMaterial: Material {
            switch self {
            case .thin: return .thinMaterial
            case .regular: return .regularMaterial
            case .thick: return .thickMaterial
            case .sidebar: return .regularMaterial
            case .hudWindow: return .ultraThinMaterial
            }
        }
    }
    
    var body: some View {
        if #available(macOS 26.0, *) {
            // macOS 26+: Will use Liquid Glass when API is available
            Rectangle().fill(.ultraThinMaterial)
        } else {
            LegacyVisualEffectView(material: style.legacyMaterial)
        }
    }
}

// MARK: - Window Configuration Helpers

/// Helper class for configuring windows based on macOS version
class WindowConfigurationHelper {
    
    /// Configures a window for the appropriate design system
    static func configureForDesignSystem(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        
        if #available(macOS 26.0, *) {
            // macOS 26+: Let system handle Liquid Glass
            // Don't set backgroundColor to clear - let the glass material show through
            window.isOpaque = false
        } else {
            // macOS 15-25: Traditional transparent window setup
            window.backgroundColor = .clear
            window.isOpaque = false
        }
        
        // Common settings
        window.styleMask.insert(.fullSizeContentView)
    }
    
    /// Configures a floating panel window
    static func configureAsFloatingPanel(_ window: NSWindow) {
        configureForDesignSystem(window)
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
    
    /// Sets up a window with visual effect background
    static func addVisualEffectBackground(to window: NSWindow, material: NSVisualEffectView.Material = .sidebar) {
        if #available(macOS 26.0, *) {
            // macOS 26+: System handles glass automatically for standard window elements
            // Only add manual glass for custom floating elements
        } else {
            // macOS 15-25: Add NSVisualEffectView manually
            let visualEffectView = NSVisualEffectView()
            visualEffectView.material = material
            visualEffectView.blendingMode = .behindWindow
            visualEffectView.state = .active
            visualEffectView.autoresizingMask = [.width, .height]
            visualEffectView.frame = window.contentView?.bounds ?? .zero
            
            if let contentView = window.contentView {
                contentView.addSubview(visualEffectView, positioned: .below, relativeTo: nil)
            }
        }
    }
}

// MARK: - Color Adaptations

extension Color {
    /// Returns an adaptive separator color for the current design system
    static var adaptiveSeparator: Color {
        if #available(macOS 26.0, *) {
            return Color.primary.opacity(0.1)
        }
        return Color.gray.opacity(0.2)
    }
    
    /// Returns an adaptive secondary background color
    static var adaptiveSecondaryBackground: Color {
        if #available(macOS 26.0, *) {
            return Color.primary.opacity(0.05)
        }
        return Color.gray.opacity(0.1)
    }
}

// MARK: - Preview

#if DEBUG
struct DesignSystemHelper_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            Text("Design System Helper")
                .font(.headline)
            
            Text("Supports Liquid Glass: \(DesignSystem.supportsLiquidGlass ? "Yes" : "No")")
            Text("Standard Corner Radius: \(Int(DesignSystem.standardCornerRadius))")
            
            Text("Sample Glass Background")
                .padding()
                .adaptiveGlassBackground()
        }
        .padding()
        .frame(width: 300, height: 200)
    }
}
#endif
