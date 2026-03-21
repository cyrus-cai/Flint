import SwiftUI
import AppKit

struct SummarizingView: View {
    // Callback to stop the summarization process when stop is pressed.
    let onStop: () -> Void
    
    // MARK: - Version-aware corner radius for macOS 26+ Liquid Glass
    private var adaptiveCornerRadius: CGFloat {
        if #available(macOS 26.0, *) {
            return 10 // Larger, softer corners for Liquid Glass
        }
        return 8 // Traditional macOS corner radius
    }

    var body: some View {
        HStack(spacing: 12) {
            // Loading indicator
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)
            
            // Summarizing status message
            Text(L("Summarizing..."))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            
            Spacer()
            
            // Stop button with macOS 26+ styling
            Button(action: {
                onStop()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10))
                    Text(L("Stop"))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    // macOS 26+ Liquid Glass 适配
                    if #available(macOS 26.0, *) {
                        Capsule()
                            .fill(.ultraThinMaterial)
                    } else {
                        Capsule()
                            .fill(Color.red.opacity(0.1))
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            // macOS 26+ Liquid Glass 适配: 浮动状态栏
            if #available(macOS 26.0, *) {
                // macOS 26+: 使用轻薄材质
                RoundedRectangle(cornerRadius: adaptiveCornerRadius)
                    .fill(.ultraThinMaterial)
            } else {
                // macOS 15-25: 使用窗口背景色
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.windowBackgroundColor))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: adaptiveCornerRadius)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }
}

struct SummarizingView_Previews: PreviewProvider {
    static var previews: some View {
        SummarizingView(onStop: {
            print("Stop pressed")
        })
        .previewLayout(.sizeThatFits)
        .padding()
    }
}
