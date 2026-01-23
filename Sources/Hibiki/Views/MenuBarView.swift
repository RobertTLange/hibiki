import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @State private var hasAccessibility = true  // Assume true initially

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status indicator
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.headline)
                Spacer()
            }

            // Current text preview (if playing)
            if let text = appState.currentText, appState.isPlaying {
                Text(text)
                    .lineLimit(3)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
            }

            // Error message
            if let error = appState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Divider()

            // Controls
            if appState.isPlaying {
                Button("Stop") {
                    appState.stopPlayback()
                }
                .keyboardShortcut(.escape)
            }

            // Permission status
            if !hasAccessibility {
                Button("Grant Accessibility Permission") {
                    PermissionManager.shared.requestAccessibilityPermission()
                }
                .foregroundColor(.orange)
            }

            Divider()

            Button("Settings...") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("Quit Hibiki") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding()
        .frame(width: 280)
        .onAppear {
            // Check permission when popover appears
            DispatchQueue.main.async {
                hasAccessibility = PermissionManager.shared.checkAccessibility()
            }
        }
    }

    private var statusColor: Color {
        if appState.isPlaying { return .green }
        if appState.isLoading { return .yellow }
        return .gray
    }

    private var statusText: String {
        if appState.isPlaying { return "Playing" }
        if appState.isLoading { return "Loading..." }
        return "Ready"
    }
}
