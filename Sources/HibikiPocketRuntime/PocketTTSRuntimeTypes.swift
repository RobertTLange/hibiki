import Foundation

public enum PocketRuntimeStatus: String {
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

public struct PocketRuntimeHealth {
    public let isHealthy: Bool
    public let statusCode: Int?
    public let message: String?
    public let isPocketAPI: Bool

    public init(isHealthy: Bool, statusCode: Int?, message: String?, isPocketAPI: Bool) {
        self.isHealthy = isHealthy
        self.statusCode = statusCode
        self.message = message
        self.isPocketAPI = isPocketAPI
    }
}

public enum PocketRuntimeError: LocalizedError {
    case uvMissing
    case invalidHost(String)
    case installFailed(step: String, output: String)
    case runtimeNotInstalled
    case startupFailed(message: String)
    case startTimedOut
    case healthCheckFailed

    public var errorDescription: String? {
        switch self {
        case .uvMissing:
            return "uv was not found. Install uv and retry Pocket TTS setup."
        case .invalidHost(let host):
            return "Managed Pocket runtime only supports localhost. Invalid host: \(host)"
        case .installFailed(let step, let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return "Pocket TTS install failed at step: \(step)."
            }
            return "Pocket TTS install failed at step: \(step). \(trimmed)"
        case .runtimeNotInstalled:
            return "Pocket TTS runtime is not installed."
        case .startupFailed(let message):
            return "Pocket TTS failed to start. \(message)"
        case .startTimedOut:
            return "Pocket TTS server did not become healthy in time."
        case .healthCheckFailed:
            return "Pocket TTS health check failed."
        }
    }
}
