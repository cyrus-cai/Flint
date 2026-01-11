//
//  VisualEffects.swift
//  Writedown
//
//  Unified visual effects for macOS 15+ with Liquid Glass support for macOS 26+
//  This file consolidates VisualEffectBlur and VisualEffectView implementations
//

import AppKit
import SwiftUI

// MARK: - Unified Visual Effect View

/// A unified NSViewRepresentable for visual effects that works across macOS versions
/// Replaces the separate VisualEffectBlur and VisualEffectView implementations
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    var state: NSVisualEffectView.State = .active
    var emphasized: Bool = false
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = emphasized
        view.wantsLayer = true
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
        nsView.isEmphasized = emphasized
    }
}

/// Alias for backward compatibility with OnboardingView.swift
typealias VisualEffectView = VisualEffectBlur

// MARK: - Liquid Glass Effect View (macOS 26+)

/// NSViewRepresentable wrapper for NSGlassEffectView (available in macOS 26+)
/// Falls back to NSVisualEffectView on older systems
struct GlassEffectView: NSViewRepresentable {
    var cornerRadius: CGFloat = 12
    var tintColor: NSColor?
    var fallbackMaterial: NSVisualEffectView.Material = .sidebar
    
    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            // macOS 26+: Use NSGlassEffectView
            // Note: This will compile when using Xcode 26 SDK
            // For now, we create a placeholder that can be updated
            let view = createGlassEffectView()
            return view
        } else {
            // Fallback for macOS 15-25
            let view = NSVisualEffectView()
            view.material = fallbackMaterial
            view.blendingMode = .withinWindow
            view.state = .active
            view.wantsLayer = true
            view.layer?.cornerRadius = cornerRadius
            view.layer?.masksToBounds = true
            return view
        }
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if #available(macOS 26.0, *) {
            // Update glass effect properties
            updateGlassEffectView(nsView)
        } else if let visualEffectView = nsView as? NSVisualEffectView {
            visualEffectView.material = fallbackMaterial
            visualEffectView.layer?.cornerRadius = cornerRadius
        }
    }
    
    @available(macOS 26.0, *)
    private func createGlassEffectView() -> NSView {
        // When Xcode 26 SDK is available, replace with:
        // let glassView = NSGlassEffectView()
        // glassView.cornerRadius = cornerRadius
        // if let tint = tintColor {
        //     glassView.tintColor = tint
        // }
        // return glassView
        
        // Temporary fallback using visual effect view with ultra-thin appearance
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .withinWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        return view
    }
    
    @available(macOS 26.0, *)
    private func updateGlassEffectView(_ nsView: NSView) {
        // When Xcode 26 SDK is available, update glass properties
        if let visualEffectView = nsView as? NSVisualEffectView {
            visualEffectView.layer?.cornerRadius = cornerRadius
        }
    }
}

// MARK: - Glass Effect Container (macOS 26+)

/// Container for grouping multiple glass elements together
/// On macOS 26+, uses NSGlassEffectContainerView for proper rendering
/// On older systems, acts as a simple transparent container
struct GlassEffectContainer<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content
    
    var body: some View {
        if #available(macOS 26.0, *) {
            // macOS 26+: Group glass elements
            content
                .background(
                    GlassContainerBackground(spacing: spacing)
                )
        } else {
            // macOS 15-25: Simple container
            content
        }
    }
}

/// Background for glass container
private struct GlassContainerBackground: NSViewRepresentable {
    var spacing: CGFloat
    
    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            // When Xcode 26 SDK is available:
            // let container = NSGlassEffectContainerView()
            // container.spacing = spacing
            // return container
            return NSView()
        } else {
            return NSView()
        }
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Adaptive Background Styles

/// Pre-defined background styles for common use cases
enum AdaptiveBackgroundStyle {
    case sidebar
    case toolbar
    case popover
    case toast
    case hudWindow
    case contentBackground
    
    var material: NSVisualEffectView.Material {
        switch self {
        case .sidebar: return .sidebar
        case .toolbar: return .headerView
        case .popover: return .popover
        case .toast: return .hudWindow
        case .hudWindow: return .hudWindow
        case .contentBackground: return .contentBackground
        }
    }
    
    var blendingMode: NSVisualEffectView.BlendingMode {
        switch self {
        case .sidebar, .toolbar, .popover, .contentBackground:
            return .withinWindow
        case .toast, .hudWindow:
            return .behindWindow
        }
    }
    
    var cornerRadius: CGFloat {
        switch self {
        case .sidebar: return 0
        case .toolbar: return 8
        case .popover: return 10
        case .toast: return 16
        case .hudWindow: return 12
        case .contentBackground: return 0
        }
    }
}

// MARK: - View Extensions for Adaptive Backgrounds

extension View {
    /// Applies a styled adaptive background
    func adaptiveBackground(style: AdaptiveBackgroundStyle) -> some View {
        self.background(
            VisualEffectBlur(
                material: style.material,
                blendingMode: style.blendingMode
            )
            .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius))
        )
    }
    
    /// Applies a glass effect background (Liquid Glass on macOS 26+)
    func glassBackground(
        cornerRadius: CGFloat = 12,
        tintColor: NSColor? = nil,
        fallbackMaterial: NSVisualEffectView.Material = .sidebar
    ) -> some View {
        self.background(
            GlassEffectView(
                cornerRadius: cornerRadius,
                tintColor: tintColor,
                fallbackMaterial: fallbackMaterial
            )
        )
    }
    
    /// Applies a sidebar-style background
    func sidebarBackground() -> some View {
        if #available(macOS 26.0, *) {
            // macOS 26+: Let system handle floating sidebar glass
            return AnyView(self)
        } else {
            return AnyView(
                self.background(
                    VisualEffectBlur(material: .sidebar)
                )
            )
        }
    }
    
    /// Applies a floating toolbar background
    func floatingToolbarBackground(cornerRadius: CGFloat = 8) -> some View {
        self.background(
            Group {
                if #available(macOS 26.0, *) {
                    // macOS 26+: Use thin material that will integrate with Liquid Glass
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                } else {
                    // macOS 15-25: Use visual effect view
                    VisualEffectBlur(material: .headerView)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                }
            }
        )
    }
}

// MARK: - Scroll Edge Effect Helpers

/// Helper for applying scroll edge effects (macOS 26+ feature)
struct ScrollEdgeEffectModifier: ViewModifier {
    var edges: Edge.Set = .top
    var style: ScrollEdgeStyle = .soft
    
    enum ScrollEdgeStyle {
        case soft  // Gradual fade
        case hard  // More opaque backing
    }
    
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            // macOS 26+: Apply scroll edge effect
            // When API is available:
            // content.scrollEdgeEffect(edges, style: style == .soft ? .soft : .hard)
            content
        } else {
            // macOS 15-25: No scroll edge effect
            content
        }
    }
}

extension View {
    func adaptiveScrollEdgeEffect(edges: Edge.Set = .top, style: ScrollEdgeEffectModifier.ScrollEdgeStyle = .soft) -> some View {
        modifier(ScrollEdgeEffectModifier(edges: edges, style: style))
    }
}

// MARK: - Preview

#if DEBUG
struct VisualEffects_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            Text("Visual Effects Preview")
                .font(.headline)
            
            VStack {
                Text("Sidebar Style")
                    .padding()
            }
            .frame(width: 200)
            .adaptiveBackground(style: .sidebar)
            
            VStack {
                Text("Glass Effect")
                    .padding()
            }
            .frame(width: 200)
            .glassBackground(cornerRadius: 12)
            
            VStack {
                Text("Floating Toolbar")
                    .padding()
            }
            .frame(width: 200)
            .floatingToolbarBackground()
        }
        .padding()
        .frame(width: 300, height: 400)
    }
}
#endif
