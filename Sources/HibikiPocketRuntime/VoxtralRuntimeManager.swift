import Foundation
import Combine
import HibikiShared

public final class VoxtralRuntimeManager: ObservableObject {
    public enum BackendKind {
        case vllmOmniLinux
        case mlxAudioAppleSilicon
        case unsupported
    }

    public static let shared = VoxtralRuntimeManager()
    private static let minimumPythonMajor = 3
    private static let minimumPythonMinor = 10
    private static let minimumPythonSpecifier = "3.10"

    @Published public private(set) var status: VoxtralRuntimeStatus = .notInstalled
    @Published public private(set) var recentLogs: [String] = []
    @Published public private(set) var installedVersion: String = "unknown"
    @Published public private(set) var lastError: String?
    @Published public private(set) var lastHealthCheckAt: Date?

    private struct RuntimePaths {
        let baseDirectory: URL
        let venvDirectory: URL
        let pythonBinary: URL
        let vllmBinary: URL
        let mlxAudioServerBinary: URL
        let logDirectory: URL
        let logFile: URL
    }

    private struct ServerLaunchConfig {
        let host: String
        let port: Int
        let modelID: String
        let apiKey: String?
        let venvPath: String?
        let autoRestart: Bool
    }

    private var serverProcess: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var logFileHandle: FileHandle?
    private let fileManager = FileManager.default
    private let ioQueue = DispatchQueue(label: "com.hibiki.voxtral-runtime.io")
    private var isStopping = false
    private var restartAttempt = 0
    private var launchConfig: ServerLaunchConfig?

    public static var backendKind: BackendKind {
        if isLinux {
            return .vllmOmniLinux
        }
        if isAppleSiliconMac {
            return .mlxAudioAppleSilicon
        }
        return .unsupported
    }

    public static var isManagedRuntimeSupportedOnCurrentPlatform: Bool {
        backendKind != .unsupported
    }

    public static var unsupportedPlatformDescription: String {
        if isLinux {
            return "Linux"
        }
        if isMacOS {
            return "this Mac configuration"
        }
        return "this platform"
    }

    public static var backendDisplayName: String {
        switch backendKind {
        case .vllmOmniLinux:
            return "vLLM Omni"
        case .mlxAudioAppleSilicon:
            return "MLX-Audio"
        case .unsupported:
            return "Unsupported"
        }
    }

    public static var defaultManagedModelID: String {
        switch backendKind {
        case .vllmOmniLinux:
            return MistralLocalTTSDefaults.modelID
        case .mlxAudioAppleSilicon:
            return MistralLocalTTSDefaults.mlxModelID
        case .unsupported:
            return MistralLocalTTSDefaults.modelID
        }
    }

    public static func defaultVenvPath() -> String {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSString(string: "~/Library/Application Support").expandingTildeInPath)
        return appSupport
            .appendingPathComponent("Hibiki", isDirectory: true)
            .appendingPathComponent("voxtral-tts", isDirectory: true)
            .appendingPathComponent(".venv", isDirectory: true)
            .path
    }

    public var isRunning: Bool {
        serverProcess?.isRunning == true && status == .running
    }

    private static var isLinux: Bool {
#if os(Linux)
        true
#else
        false
#endif
    }

    private static var isMacOS: Bool {
#if os(macOS)
        true
#else
        false
#endif
    }

    private static var isAppleSiliconMac: Bool {
#if os(macOS)
        return sysctlFlag(named: "hw.optional.arm64") == 1
#else
        return false
#endif
    }

    private static func sysctlFlag(named name: String) -> Int32 {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname(name, &value, &size, nil, 0)
        return result == 0 ? value : 0
    }

    public func hasInstalledRuntime(venvPath: String? = nil) -> Bool {
        guard Self.isManagedRuntimeSupportedOnCurrentPlatform else {
            return false
        }
        let paths = runtimePaths(venvPath: venvPath)
        let runtimeBinaryInstalled: Bool
        switch Self.backendKind {
        case .vllmOmniLinux:
            runtimeBinaryInstalled = fileManager.isExecutableFile(atPath: paths.vllmBinary.path)
        case .mlxAudioAppleSilicon:
            runtimeBinaryInstalled = fileManager.isExecutableFile(atPath: paths.mlxAudioServerBinary.path)
        case .unsupported:
            runtimeBinaryInstalled = false
        }

        return runtimeBinaryInstalled && fileManager.isExecutableFile(atPath: paths.pythonBinary.path)
    }

    @MainActor
    public func installIfNeeded(venvPath: String? = nil) async throws {
        guard Self.isManagedRuntimeSupportedOnCurrentPlatform else {
            status = .failed
            lastError = VoxtralRuntimeError.unsupportedPlatform(Self.unsupportedPlatformDescription).localizedDescription
            throw VoxtralRuntimeError.unsupportedPlatform(Self.unsupportedPlatformDescription)
        }
        let paths = runtimePaths(venvPath: venvPath)
        let runtimeBinaryInstalled: Bool
        switch Self.backendKind {
        case .vllmOmniLinux:
            runtimeBinaryInstalled = fileManager.isExecutableFile(atPath: paths.vllmBinary.path)
        case .mlxAudioAppleSilicon:
            runtimeBinaryInstalled = fileManager.isExecutableFile(atPath: paths.mlxAudioServerBinary.path)
        case .unsupported:
            runtimeBinaryInstalled = false
        }

        if runtimeBinaryInstalled,
           fileManager.isExecutableFile(atPath: paths.pythonBinary.path),
           let isSupported = try await isManagedPythonVersionSupported(pythonBinary: paths.pythonBinary.path),
           isSupported {
            status = .installed
            try await refreshInstalledVersion(venvPath: venvPath)
            return
        }

        if fileManager.fileExists(atPath: paths.venvDirectory.path) {
            appendLogLine("Existing managed venv is incompatible; reinstalling with Python 3.10+.")
        }
        try await reinstall(venvPath: venvPath)
    }

    @MainActor
    public func reinstall(venvPath: String? = nil) async throws {
        guard Self.isManagedRuntimeSupportedOnCurrentPlatform else {
            status = .failed
            lastError = VoxtralRuntimeError.unsupportedPlatform(Self.unsupportedPlatformDescription).localizedDescription
            throw VoxtralRuntimeError.unsupportedPlatform(Self.unsupportedPlatformDescription)
        }
        status = .installing
        lastError = nil
        appendLogLine("Installing Voxtral runtime with uv...")

        guard let uvBinary = resolveUVBinary() else {
            status = .failed
            lastError = VoxtralRuntimeError.uvMissing.localizedDescription
            throw VoxtralRuntimeError.uvMissing
        }

        let paths = runtimePaths(venvPath: venvPath)
        try ensureDirectories(paths: paths)

        if fileManager.fileExists(atPath: paths.venvDirectory.path) {
            do {
                try fileManager.removeItem(at: paths.venvDirectory)
            } catch {
                status = .failed
                lastError = VoxtralRuntimeError.installFailed(
                    step: "remove incompatible venv",
                    output: error.localizedDescription
                ).localizedDescription
                throw VoxtralRuntimeError.installFailed(
                    step: "remove incompatible venv",
                    output: error.localizedDescription
                )
            }
        }

        let createVenvResult = try await runCommand(
            executablePath: uvBinary,
            arguments: [
                "venv",
                paths.venvDirectory.path,
                "--python",
                Self.minimumPythonSpecifier
            ]
        )
        guard createVenvResult.exitCode == 0 else {
            status = .failed
            lastError = VoxtralRuntimeError.installFailed(step: "uv venv", output: createVenvResult.output).localizedDescription
            throw VoxtralRuntimeError.installFailed(step: "uv venv", output: createVenvResult.output)
        }

        if let isSupported = try await isManagedPythonVersionSupported(pythonBinary: paths.pythonBinary.path),
           !isSupported {
            status = .failed
            let output = "Managed venv uses unsupported Python version. Voxtral requires Python >=3.10."
            lastError = VoxtralRuntimeError.installFailed(step: "python version check", output: output).localizedDescription
            throw VoxtralRuntimeError.installFailed(step: "python version check", output: output)
        }

        switch Self.backendKind {
        case .vllmOmniLinux:
            let installVLLMResult = try await runCommand(
                executablePath: uvBinary,
                arguments: [
                    "pip",
                    "install",
                    "--python",
                    paths.pythonBinary.path,
                    "--upgrade",
                    "vllm>=0.18.0"
                ]
            )
            guard installVLLMResult.exitCode == 0 else {
                status = .failed
                lastError = VoxtralRuntimeError.installFailed(step: "uv pip install vllm", output: installVLLMResult.output).localizedDescription
                throw VoxtralRuntimeError.installFailed(step: "uv pip install vllm", output: installVLLMResult.output)
            }

            let installOmniResult = try await runCommand(
                executablePath: uvBinary,
                arguments: [
                    "pip",
                    "install",
                    "--python",
                    paths.pythonBinary.path,
                    "--upgrade",
                    "git+https://github.com/vllm-project/vllm-omni.git"
                ]
            )
            guard installOmniResult.exitCode == 0 else {
                status = .failed
                lastError = VoxtralRuntimeError.installFailed(step: "uv pip install vllm-omni", output: installOmniResult.output).localizedDescription
                throw VoxtralRuntimeError.installFailed(step: "uv pip install vllm-omni", output: installOmniResult.output)
            }
        case .mlxAudioAppleSilicon:
            let installMLXAudioResult = try await runCommand(
                executablePath: uvBinary,
                arguments: [
                    "pip",
                    "install",
                    "--python",
                    paths.pythonBinary.path,
                    "--upgrade",
                    "mlx-audio[all]"
                ]
            )
            guard installMLXAudioResult.exitCode == 0 else {
                status = .failed
                lastError = VoxtralRuntimeError.installFailed(step: "uv pip install mlx-audio", output: installMLXAudioResult.output).localizedDescription
                throw VoxtralRuntimeError.installFailed(step: "uv pip install mlx-audio", output: installMLXAudioResult.output)
            }
        case .unsupported:
            break
        }

        try await refreshInstalledVersion(venvPath: venvPath)
        status = .installed
        appendLogLine("Voxtral runtime installation complete.")
    }

    @MainActor
    public func startServer(
        host: String,
        port: Int,
        modelID: String,
        apiKey: String? = nil,
        venvPath: String? = nil,
        autoRestart: Bool = false
    ) async throws {
        guard Self.isManagedRuntimeSupportedOnCurrentPlatform else {
            status = .failed
            lastError = VoxtralRuntimeError.unsupportedPlatform(Self.unsupportedPlatformDescription).localizedDescription
            throw VoxtralRuntimeError.unsupportedPlatform(Self.unsupportedPlatformDescription)
        }
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isLoopbackHost(normalizedHost) else {
            let error = VoxtralRuntimeError.invalidHost(normalizedHost)
            status = .failed
            lastError = error.localizedDescription
            throw error
        }

        let effectiveModelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.defaultManagedModelID
            : modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveAPIKey = normalizedOptional(apiKey)
        let paths = runtimePaths(venvPath: venvPath)

        let executableURL: URL?
        switch Self.backendKind {
        case .vllmOmniLinux:
            executableURL = fileManager.isExecutableFile(atPath: paths.vllmBinary.path) ? paths.vllmBinary : nil
        case .mlxAudioAppleSilicon:
            executableURL = fileManager.isExecutableFile(atPath: paths.mlxAudioServerBinary.path) ? paths.mlxAudioServerBinary : nil
        case .unsupported:
            executableURL = nil
        }

        guard let executableURL else {
            status = .failed
            lastError = VoxtralRuntimeError.runtimeNotInstalled.localizedDescription
            throw VoxtralRuntimeError.runtimeNotInstalled
        }

        stopServer()

        try ensureDirectories(paths: paths)
        try openLogHandle(paths: paths)

        isStopping = false
        status = .starting
        lastError = nil
        launchConfig = ServerLaunchConfig(
            host: normalizedHost,
            port: port,
            modelID: effectiveModelID,
            apiKey: effectiveAPIKey,
            venvPath: venvPath,
            autoRestart: autoRestart
        )
        appendLogLine("Starting Voxtral server on \(normalizedHost):\(port)")

        let process = Process()
        process.executableURL = executableURL
        var arguments: [String]
        switch Self.backendKind {
        case .vllmOmniLinux:
            arguments = [
                "serve",
                effectiveModelID,
                "--omni",
                "--host", normalizedHost,
                "--port", String(port),
            ]
            if let effectiveAPIKey {
                arguments.append(contentsOf: ["--api-key", effectiveAPIKey])
            }
        case .mlxAudioAppleSilicon:
            arguments = [
                "--host", normalizedHost,
                "--port", String(port),
                "--log-dir", paths.logDirectory.path,
            ]
        case .unsupported:
            arguments = []
        }
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        self.serverProcess = process

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.recordProcessOutput(data)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.recordProcessOutput(data)
        }

        process.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                self?.handleProcessTermination(exitCode: process.terminationStatus)
            }
        }

        do {
            try process.run()
        } catch {
            status = .failed
            lastError = VoxtralRuntimeError.startupFailed(message: error.localizedDescription).localizedDescription
            cleanupPipesAndHandles()
            throw VoxtralRuntimeError.startupFailed(message: error.localizedDescription)
        }

        let baseURL = Self.baseURL(host: normalizedHost, port: port)
        let healthy = await waitForHealthy(baseURL: baseURL, apiKey: effectiveAPIKey, timeoutSeconds: 25)
        if healthy, serverProcess?.isRunning == true {
            status = .running
            restartAttempt = 0
            appendLogLine("Voxtral server is healthy.")
            return
        }

        stopServer()
        status = .failed
        lastError = VoxtralRuntimeError.startTimedOut.localizedDescription
        throw VoxtralRuntimeError.startTimedOut
    }

    @MainActor
    public func stopServer() {
        guard let process = serverProcess else {
            status = .stopped
            cleanupPipesAndHandles()
            return
        }

        isStopping = true
        if process.isRunning {
            process.terminate()
        }

        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        status = .stopped
    }

    @MainActor
    public func restartServer(
        host: String,
        port: Int,
        modelID: String,
        apiKey: String? = nil,
        venvPath: String? = nil,
        autoRestart: Bool = false
    ) async throws {
        stopServer()
        try await startServer(
            host: host,
            port: port,
            modelID: modelID,
            apiKey: apiKey,
            venvPath: venvPath,
            autoRestart: autoRestart
        )
    }

    @MainActor
    public func healthCheck(baseURL: String, apiKey: String?) async -> VoxtralRuntimeHealth {
        guard let voicesURL = voicesURL(baseURL: baseURL) else {
            return VoxtralRuntimeHealth(isHealthy: false, statusCode: nil, message: "Invalid base URL", isVoxtralAPI: false)
        }

        var request = URLRequest(url: voicesURL)
        request.timeoutInterval = 2.0
        if let token = normalizedOptional(apiKey) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpStatus = (response as? HTTPURLResponse)?.statusCode
            lastHealthCheckAt = Date()
            if httpStatus == 200, voicesPayloadLooksHealthy(data) {
                return VoxtralRuntimeHealth(
                    isHealthy: true,
                    statusCode: 200,
                    message: nil,
                    isVoxtralAPI: true
                )
            }
        } catch {
        }

        guard let openAPIURL = openAPIURL(baseURL: baseURL) else {
            return VoxtralRuntimeHealth(
                isHealthy: false,
                statusCode: nil,
                message: "Invalid base URL",
                isVoxtralAPI: false
            )
        }

        var openAPIRequest = URLRequest(url: openAPIURL)
        openAPIRequest.timeoutInterval = 2.0
        if let token = normalizedOptional(apiKey) {
            openAPIRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: openAPIRequest)
            let httpStatus = (response as? HTTPURLResponse)?.statusCode
            lastHealthCheckAt = Date()
            guard httpStatus == 200 else {
                return VoxtralRuntimeHealth(
                    isHealthy: false,
                    statusCode: httpStatus,
                    message: "HTTP \(httpStatus ?? -1)",
                    isVoxtralAPI: false
                )
            }

            if openAPIHasSpeechEndpoint(data) {
                return VoxtralRuntimeHealth(
                    isHealthy: true,
                    statusCode: 200,
                    message: nil,
                    isVoxtralAPI: true
                )
            }

            return VoxtralRuntimeHealth(
                isHealthy: false,
                statusCode: httpStatus,
                message: "OpenAPI payload is not Voxtral-compatible.",
                isVoxtralAPI: false
            )
        } catch {
            return VoxtralRuntimeHealth(
                isHealthy: false,
                statusCode: nil,
                message: error.localizedDescription,
                isVoxtralAPI: false
            )
        }
    }

    @MainActor
    public func clearLastError() {
        lastError = nil
    }

    @MainActor
    private func waitForHealthy(baseURL: String, apiKey: String?, timeoutSeconds: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if Task.isCancelled {
                return false
            }
            guard serverProcess?.isRunning == true else {
                return false
            }
            let health = await healthCheck(baseURL: baseURL, apiKey: apiKey)
            if health.isHealthy {
                return true
            }
            guard serverProcess?.isRunning == true else {
                return false
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return false
    }

    @MainActor
    private func refreshInstalledVersion(venvPath: String? = nil) async throws {
        let paths = runtimePaths(venvPath: venvPath)
        guard fileManager.isExecutableFile(atPath: paths.pythonBinary.path) else {
            installedVersion = "unknown"
            return
        }

        let result = try await runCommand(
            executablePath: paths.pythonBinary.path,
            arguments: [
                "-c",
                packageVersionCheckScript()
            ]
        )

        guard result.exitCode == 0 else {
            installedVersion = "unknown"
            return
        }
        let trimmed = result.output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n")
            .last
            .map(String.init)
        installedVersion = trimmed?.isEmpty == false ? trimmed! : "unknown"
    }

    @MainActor
    private func handleProcessTermination(exitCode: Int32) {
        defer {
            serverProcess = nil
            cleanupPipesAndHandles()
        }

        if isStopping {
            isStopping = false
            status = .stopped
            appendLogLine("Voxtral server stopped.")
            return
        }

        appendLogLine("Voxtral server exited unexpectedly (\(exitCode)).")

        guard let config = launchConfig, config.autoRestart, restartAttempt < 5 else {
            status = .failed
            lastError = "Voxtral server exited unexpectedly (code \(exitCode))."
            return
        }

        let delays: [UInt64] = [1, 2, 5, 5, 5]
        let delaySeconds = delays[min(restartAttempt, delays.count - 1)]
        restartAttempt += 1
        status = .unhealthy
        appendLogLine("Restarting Voxtral in \(delaySeconds)s (attempt \(restartAttempt)/5)")

        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
            guard self.serverProcess == nil else { return }
            do {
                try await self.startServer(
                    host: config.host,
                    port: config.port,
                    modelID: config.modelID,
                    apiKey: config.apiKey,
                    venvPath: config.venvPath,
                    autoRestart: config.autoRestart
                )
            } catch {
                self.status = .failed
                self.lastError = error.localizedDescription
            }
        }
    }

    private func runtimePaths(venvPath: String?) -> RuntimePaths {
        let resolvedVenvPath = normalizedPath(venvPath ?? Self.defaultVenvPath())
        let venvDirectory = URL(fileURLWithPath: resolvedVenvPath, isDirectory: true)
        let baseDirectory = venvDirectory.deletingLastPathComponent()
        let logDirectory = baseDirectory.appendingPathComponent("logs", isDirectory: true)
        return RuntimePaths(
            baseDirectory: baseDirectory,
            venvDirectory: venvDirectory,
            pythonBinary: venvDirectory.appendingPathComponent("bin/python"),
            vllmBinary: venvDirectory.appendingPathComponent("bin/vllm"),
            mlxAudioServerBinary: venvDirectory.appendingPathComponent("bin/mlx_audio.server"),
            logDirectory: logDirectory,
            logFile: logDirectory.appendingPathComponent("server.log")
        )
    }

    private func normalizedPath(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }

    private func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func ensureDirectories(paths: RuntimePaths) throws {
        try fileManager.createDirectory(at: paths.baseDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.logDirectory, withIntermediateDirectories: true)
    }

    private func openLogHandle(paths: RuntimePaths) throws {
        if !fileManager.fileExists(atPath: paths.logFile.path) {
            fileManager.createFile(atPath: paths.logFile.path, contents: Data())
        }
        let handle = try FileHandle(forWritingTo: paths.logFile)
        handle.seekToEndOfFile()
        logFileHandle = handle
    }

    private func cleanupPipesAndHandles() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe = nil

        ioQueue.async { [weak self] in
            self?.logFileHandle?.closeFile()
            self?.logFileHandle = nil
        }
    }

    private func recordProcessOutput(_ data: Data) {
        ioQueue.async { [weak self] in
            guard let self else { return }

            self.logFileHandle?.write(data)

            guard let text = String(data: data, encoding: .utf8) else { return }
            let lines = text
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

            guard !lines.isEmpty else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.recentLogs.append(contentsOf: lines)
                if self.recentLogs.count > 200 {
                    self.recentLogs.removeFirst(self.recentLogs.count - 200)
                }
            }
        }
    }

    @MainActor
    private func appendLogLine(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentLogs.append(trimmed)
        if recentLogs.count > 200 {
            recentLogs.removeFirst(recentLogs.count - 200)
        }
    }

    private func runCommand(
        executablePath: String,
        arguments: [String]
    ) async throws -> (exitCode: Int32, output: String) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.environment = ProcessInfo.processInfo.environment

            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            process.terminationHandler = { process in
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: (process.terminationStatus, output))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func isManagedPythonVersionSupported(pythonBinary: String) async throws -> Bool? {
        guard fileManager.isExecutableFile(atPath: pythonBinary) else {
            return nil
        }

        let result = try await runCommand(
            executablePath: pythonBinary,
            arguments: [
                "-c",
                "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
            ]
        )

        guard result.exitCode == 0 else {
            return nil
        }

        let versionLine = result.output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n")
            .last
            .map(String.init)

        guard let versionLine,
              let major = Int(versionLine.split(separator: ".").first ?? ""),
              let minorString = versionLine.split(separator: ".").dropFirst().first,
              let minor = Int(minorString) else {
            return nil
        }

        if major > Self.minimumPythonMajor {
            return true
        }
        if major == Self.minimumPythonMajor && minor >= Self.minimumPythonMinor {
            return true
        }
        return false
    }

    private func resolveUVBinary() -> String? {
        let environment = ProcessInfo.processInfo.environment
        if let pathValue = environment["PATH"] {
            let paths = pathValue.split(separator: ":").map(String.init)
            for directory in paths {
                let candidate = URL(fileURLWithPath: directory).appendingPathComponent("uv").path
                if fileManager.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }

        let home = NSHomeDirectory()
        let fallbackCandidates = [
            "\(home)/.local/bin/uv",
            "/opt/homebrew/bin/uv",
            "/usr/local/bin/uv"
        ]
        for candidate in fallbackCandidates where fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return nil
    }

    private func voicesPayloadLooksHealthy(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let voices = json["voices"] as? [String] else {
            return false
        }
        return !voices.isEmpty
    }

    private func openAPIHasSpeechEndpoint(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let paths = json["paths"] as? [String: Any] else {
            return false
        }
        return paths["/v1/audio/speech"] != nil || paths["/audio/speech"] != nil
    }

    private func voicesURL(baseURL: String) -> URL? {
        guard var components = URLComponents(string: baseURL) else { return nil }
        let path = components.path
        if path.isEmpty || path == "/" {
            components.path = "/v1/audio/voices"
        } else if path.hasSuffix("/v1/audio/voices") {
            return components.url
        } else if path.hasSuffix("/v1") {
            components.path = "\(path)/audio/voices"
        } else {
            components.path = path.hasSuffix("/") ? "\(path)v1/audio/voices" : "\(path)/v1/audio/voices"
        }
        return components.url
    }

    private func openAPIURL(baseURL: String) -> URL? {
        URL(string: baseURL)?.appending(path: "openapi.json")
    }

    private func packageVersionCheckScript() -> String {
        switch Self.backendKind {
        case .vllmOmniLinux:
            return "import importlib.metadata as m; print(m.version('vllm'))"
        case .mlxAudioAppleSilicon:
            return "import importlib.metadata as m; print(m.version('mlx-audio'))"
        case .unsupported:
            return "print('unknown')"
        }
    }

    public static func baseURL(host: String, port: Int) -> String {
        "http://\(host):\(port)"
    }

    private static func isLoopbackHost(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "127.0.0.1" || normalized == "localhost" || normalized == "::1"
    }
}
