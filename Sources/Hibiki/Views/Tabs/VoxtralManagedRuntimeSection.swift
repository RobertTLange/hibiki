import SwiftUI
import HibikiPocketRuntime

struct VoxtralManagedRuntimeSection: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var voxtralRuntimeManager = VoxtralRuntimeManager.shared
    @State private var isInstallingRuntime = false
    @State private var isStartingRuntime = false
    @State private var isRestartingRuntime = false

    private var managedRuntimeSupported: Bool {
        VoxtralRuntimeManager.isManagedRuntimeSupportedOnCurrentPlatform
    }

    private var unsupportedRuntimeMessage: String {
        VoxtralRuntimeError
            .unsupportedPlatform(VoxtralRuntimeManager.unsupportedPlatformDescription)
            .localizedDescription
    }

    private var backendSummary: String {
        switch VoxtralRuntimeManager.backendKind {
        case .vllmOmniLinux:
            return "Backend: vLLM Omni on Linux GPU."
        case .mlxAudioAppleSilicon:
            return "Backend: MLX-Audio on Apple Silicon."
        case .unsupported:
            return "Backend unavailable on this platform."
        }
    }

    private var statusIcon: String {
        switch voxtralRuntimeManager.status {
        case .running:
            return "checkmark.circle.fill"
        case .installing, .starting:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .unhealthy, .failed:
            return "xmark.circle.fill"
        case .installed, .stopped:
            return "pause.circle.fill"
        case .notInstalled:
            return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch voxtralRuntimeManager.status {
        case .running:
            return .green
        case .installing, .starting:
            return .orange
        case .installed, .stopped:
            return .secondary
        case .unhealthy, .failed, .notInstalled:
            return .red
        }
    }

    var body: some View {
        GroupBox("Local Voxtral TTS (Managed)") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Enable managed runtime", isOn: $appState.mistralManagedEnabled)
                Toggle("Auto-start with Hibiki", isOn: $appState.mistralManagedAutoStart)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Host")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("127.0.0.1", text: $appState.mistralManagedHost)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Port")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("8091", value: $appState.mistralManagedPort, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Model")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(appState.mistralLocalModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                             ? TTSConfiguration.defaultMistralLocalModelID
                             : appState.mistralLocalModelID)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Managed venv path")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("", text: $appState.mistralManagedVenvPath)
                        .textFieldStyle(.roundedBorder)
                }

                Text("Uses the Voxtral provider settings above for model ID, API key, voice preset, and request timeout.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(backendSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if !managedRuntimeSupported {
                    Text(unsupportedRuntimeMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                HStack(spacing: 8) {
                    Image(systemName: statusIcon)
                        .foregroundColor(statusColor)
                    Text(voxtralRuntimeManager.status.displayName)
                        .font(.system(.caption, design: .monospaced))
                    Text("v\(voxtralRuntimeManager.installedVersion)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    if let date = voxtralRuntimeManager.lastHealthCheckAt {
                        Text("health \(date.formatted(date: .omitted, time: .standard))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Button("Install / Reinstall") {
                        Task {
                            isInstallingRuntime = true
                            await appState.installMistralRuntime()
                            isInstallingRuntime = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!managedRuntimeSupported || isInstallingRuntime || isStartingRuntime || isRestartingRuntime)

                    Button("Start") {
                        Task {
                            isStartingRuntime = true
                            await appState.startMistralRuntime()
                            isStartingRuntime = false
                        }
                    }
                    .disabled(!managedRuntimeSupported || isInstallingRuntime || isStartingRuntime || isRestartingRuntime)

                    Button("Stop") {
                        appState.stopMistralRuntime()
                    }
                    .disabled(!managedRuntimeSupported || isInstallingRuntime || isStartingRuntime || isRestartingRuntime)

                    Button("Restart") {
                        Task {
                            isRestartingRuntime = true
                            await appState.restartMistralRuntime()
                            isRestartingRuntime = false
                        }
                    }
                    .disabled(!managedRuntimeSupported || isInstallingRuntime || isStartingRuntime || isRestartingRuntime)

                    Button("Health Check") {
                        Task {
                            await appState.runMistralRuntimeHealthCheckWithReadout()
                        }
                    }
                    .disabled(!managedRuntimeSupported || isInstallingRuntime || isStartingRuntime || isRestartingRuntime)

                    if isInstallingRuntime || isStartingRuntime || isRestartingRuntime {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }

                if !appState.mistralManagedLastError.isEmpty {
                    Text(appState.mistralManagedLastError)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                if !voxtralRuntimeManager.recentLogs.isEmpty {
                    Text(voxtralRuntimeManager.recentLogs.suffix(4).joined(separator: "\n"))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
