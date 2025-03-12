import SwiftUI

struct SummarizingView: View {
    // Callback to stop the summarization process when stop is pressed.
    let onStop: () -> Void

    var body: some View {
        HStack {
            // Summarizing status message
            Text("Summarizing...")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer() // Pushes the stop button to the right.
            // Stop button
            Button(action: {
                onStop()
            }) {
                Text("停止")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless) // Style for a light border or none.
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct SummarizingView_Previews: PreviewProvider {
    static var previews: some View {
        SummarizingView(onStop: {
            print("Stop pressed")
        })
        .previewLayout(.sizeThatFits)
    }
}