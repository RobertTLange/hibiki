import Foundation

public enum VoxtralRuntimeStatus: String {
    case notInstalled
    case installing
    case installed
    case starting
    case running
    case unhealthy
    case stopped
    case failed

    public var displayName: String {
        switch self {
        case .notInstalled: return "Not installed"
        case .installing: return "Installing"
        case .installed: return "Installed"
        case .starting: return "Starting"
        case .running: return "Running"
        case .unhealthy: return "Unhealthy"
        case .stopped: return "Stopped"
        case .failed: return "Failed"
        }
    }
}

public struct VoxtralRuntimeHealth {
    public let isHealthy: Bool
    public let statusCode: Int?
    public let message: String?
    public let isVoxtralAPI: Bool

    public init(isHealthy: Bool, statusCode: Int?, message: String?, isVoxtralAPI: Bool) {
        self.isHealthy = isHealthy
        self.statusCode = statusCode
        self.message = message
        self.isVoxtralAPI = isVoxtralAPI
    }
}

public enum VoxtralRuntimeError: LocalizedError {
    case unsupportedPlatform(String)
    case uvMissing
    case invalidHost(String)
    case installFailed(step: String, output: String)
    case runtimeNotInstalled
    case startupFailed(message: String)
    case startTimedOut
    case healthCheckFailed

    public var errorDescription: String? {
        switch self {
        case .unsupportedPlatform(let platform):
            return "Managed Voxtral runtime is not supported on \(platform). Use a manual endpoint backed by a Linux GPU host running vllm/vllm-omni."
        case .uvMissing:
            return "uv was not found. Install uv and retry Voxtral setup."
        case .invalidHost(let host):
            return "Managed Voxtral runtime only supports localhost. Invalid host: \(host)"
        case .installFailed(let step, let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return "Voxtral install failed at step: \(step)."
            }
            return "Voxtral install failed at step: \(step). \(trimmed)"
        case .runtimeNotInstalled:
            return "Voxtral runtime is not installed."
        case .startupFailed(let message):
            return "Voxtral failed to start. \(message)"
        case .startTimedOut:
            return "Voxtral server did not become healthy in time."
        case .healthCheckFailed:
            return "Voxtral health check failed."
        }
    }
}
