import Foundation
import Combine
public final class PocketTTSRuntimeManager: ObservableObject {
    public static let shared = PocketTTSRuntimeManager()
    private static let minimumPythonMajor = 3
    private static let minimumPythonMinor = 10
    private static let minimumPythonSpecifier = "3.10"

    @Published public private(set) var status: PocketRuntimeStatus = .notInstalled
    @Published public private(set) var recentLogs: [String] = []
    @Published public private(set) var installedVersion: String = "unknown"
    @Published public private(set) var lastError: String?
    @Published public private(set) var lastHealthCheckAt: Date?

    private struct RuntimePaths {
        let baseDirectory: URL
        let venvDirectory: URL
        let pythonBinary: URL
        let pocketBinary: URL
        let logDirectory: URL
        let logFile: URL
    }

    private struct ServerLaunchConfig {
        let host: String
        let port: Int
        let voice: String
        let venvPath: String?
        let autoRestart: Bool
    }

    private var serverProcess: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var logFileHandle: FileHandle?
    private let fileManager = FileManager.default
    private let ioQueue = DispatchQueue(label: "com.hibiki.pocket-runtime.io")
    private var isStopping = false
    private var restartAttempt = 0
    private var launchConfig: ServerLaunchConfig?
    public static func defaultVenvPath() -> String {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSString(string: "~/Library/Application Support").expandingTildeInPath)
        return appSupport
            .appendingPathComponent("Hibiki", isDirectory: true)
            .appendingPathComponent("pocket-tts", isDirectory: true)
            .appendingPathComponent(".venv", isDirectory: true)
            .path
    }

    public var isRunning: Bool {
        serverProcess?.isRunning == true && status == .running
    }

    public func hasInstalledRuntime(venvPath: String? = nil) -> Bool {
        let paths = runtimePaths(venvPath: venvPath)
        return fileManager.isExecutableFile(atPath: paths.pocketBinary.path) &&
            fileManager.isExecutableFile(atPath: paths.pythonBinary.path)
    }

    @MainActor
    public func installIfNeeded(venvPath: String? = nil) async throws {
        let paths = runtimePaths(venvPath: venvPath)
        if fileManager.isExecutableFile(atPath: paths.pocketBinary.path),
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
        status = .installing
        lastError = nil
        appendLogLine("Installing Pocket TTS runtime with uv...")

        guard let uvBinary = resolveUVBinary() else {
            status = .failed
            lastError = PocketRuntimeError.uvMissing.localizedDescription
            throw PocketRuntimeError.uvMissing
        }

        let paths = runtimePaths(venvPath: venvPath)
        try ensureDirectories(paths: paths)

        if fileManager.fileExists(atPath: paths.venvDirectory.path) {
            do {
                try fileManager.removeItem(at: paths.venvDirectory)
            } catch {
                status = .failed
                lastError = PocketRuntimeError.installFailed(
                    step: "remove incompatible venv",
                    output: error.localizedDescription
                ).localizedDescription
                throw PocketRuntimeError.installFailed(
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
            lastError = PocketRuntimeError.installFailed(step: "uv venv", output: createVenvResult.output).localizedDescription
            throw PocketRuntimeError.installFailed(step: "uv venv", output: createVenvResult.output)
        }

        if let isSupported = try await isManagedPythonVersionSupported(pythonBinary: paths.pythonBinary.path),
           !isSupported {
            status = .failed
            let output = "Managed venv uses unsupported Python version. pocket-tts requires Python >=3.10."
            lastError = PocketRuntimeError.installFailed(step: "python version check", output: output).localizedDescription
            throw PocketRuntimeError.installFailed(step: "python version check", output: output)
        }

        let installResult = try await runCommand(
            executablePath: uvBinary,
            arguments: [
                "pip",
                "install",
                "--python",
                paths.pythonBinary.path,
                "--upgrade",
                "pocket-tts"
            ]
        )
        guard installResult.exitCode == 0 else {
            status = .failed
            lastError = PocketRuntimeError.installFailed(step: "uv pip install", output: installResult.output).localizedDescription
            throw PocketRuntimeError.installFailed(step: "uv pip install", output: installResult.output)
        }

        try await refreshInstalledVersion(venvPath: venvPath)
        status = .installed
        appendLogLine("Pocket TTS runtime installation complete.")
    }

    @MainActor
    public func startServer(
        host: String,
        port: Int,
        voice: String,
        venvPath: String? = nil,
        autoRestart: Bool = false
    ) async throws {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isLoopbackHost(normalizedHost) else {
            let error = PocketRuntimeError.invalidHost(normalizedHost)
            status = .failed
            lastError = error.localizedDescription
            throw error
        }

        let normalizedVoice = voice.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveVoice = normalizedVoice.isEmpty ? "alba" : normalizedVoice
        let paths = runtimePaths(venvPath: venvPath)

        guard fileManager.isExecutableFile(atPath: paths.pocketBinary.path) else {
            status = .failed
            lastError = PocketRuntimeError.runtimeNotInstalled.localizedDescription
            throw PocketRuntimeError.runtimeNotInstalled
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
            voice: effectiveVoice,
            venvPath: venvPath,
            autoRestart: autoRestart
        )
        appendLogLine("Starting Pocket TTS server on \(normalizedHost):\(port)")

        let process = Process()
        process.executableURL = paths.pocketBinary
        process.arguments = [
            "serve",
            "--host", normalizedHost,
            "--port", String(port),
            "--voice", effectiveVoice
        ]
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
            lastError = PocketRuntimeError.startupFailed(message: error.localizedDescription).localizedDescription
            cleanupPipesAndHandles()
            throw PocketRuntimeError.startupFailed(message: error.localizedDescription)
        }

        let baseURL = Self.baseURL(host: normalizedHost, port: port)
        let healthy = await waitForHealthy(baseURL: baseURL, timeoutSeconds: 20)
        if healthy, serverProcess?.isRunning == true {
            status = .running
            restartAttempt = 0
            appendLogLine("Pocket TTS server is healthy.")
            return
        }

        stopServer()
        status = .failed
        lastError = PocketRuntimeError.startTimedOut.localizedDescription
        throw PocketRuntimeError.startTimedOut
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
        voice: String,
        venvPath: String? = nil,
        autoRestart: Bool = false
    ) async throws {
        stopServer()
        try await startServer(
            host: host,
            port: port,
            voice: voice,
            venvPath: venvPath,
            autoRestart: autoRestart
        )
    }

    @MainActor
    public func healthCheck(baseURL: String) async -> PocketRuntimeHealth {
        guard let url = URL(string: baseURL)?.appending(path: "health") else {
            return PocketRuntimeHealth(isHealthy: false, statusCode: nil, message: "Invalid base URL", isPocketAPI: false)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpStatus = (response as? HTTPURLResponse)?.statusCode
            lastHealthCheckAt = Date()
            guard httpStatus == 200 else {
                return PocketRuntimeHealth(
                    isHealthy: false,
                    statusCode: httpStatus,
                    message: "HTTP \(httpStatus ?? -1)",
                    isPocketAPI: false
                )
            }

            guard healthPayloadLooksHealthy(data) else {
                return PocketRuntimeHealth(
                    isHealthy: false,
                    statusCode: httpStatus,
                    message: "Health payload is not Pocket TTS.",
                    isPocketAPI: false
                )
            }

            let isPocket = await pocketOpenAPIIsReachable(baseURL: baseURL)
            if !isPocket {
                return PocketRuntimeHealth(
                    isHealthy: false,
                    statusCode: httpStatus,
                    message: "Another service appears to be running on this port.",
                    isPocketAPI: false
                )
            }

            return PocketRuntimeHealth(
                isHealthy: true,
                statusCode: 200,
                message: nil,
                isPocketAPI: true
            )
        } catch {
            return PocketRuntimeHealth(
                isHealthy: false,
                statusCode: nil,
                message: error.localizedDescription,
                isPocketAPI: false
            )
        }
    }

    @MainActor
    public func clearLastError() {
        lastError = nil
    }

    @MainActor
    private func waitForHealthy(baseURL: String, timeoutSeconds: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if Task.isCancelled {
                return false
            }
            guard serverProcess?.isRunning == true else {
                return false
            }
            let health = await healthCheck(baseURL: baseURL)
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
                "import importlib.metadata as m; print(m.version('pocket-tts'))"
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
            appendLogLine("Pocket TTS server stopped.")
            return
        }

        appendLogLine("Pocket TTS server exited unexpectedly (\(exitCode)).")

        guard let config = launchConfig, config.autoRestart, restartAttempt < 5 else {
            status = .failed
            lastError = "Pocket TTS server exited unexpectedly (code \(exitCode))."
            return
        }

        let delays: [UInt64] = [1, 2, 5, 5, 5]
        let delaySeconds = delays[min(restartAttempt, delays.count - 1)]
        restartAttempt += 1
        status = .unhealthy
        appendLogLine("Restarting Pocket TTS in \(delaySeconds)s (attempt \(restartAttempt)/5)")

        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
            guard self.serverProcess == nil else { return }
            do {
                try await self.startServer(
                    host: config.host,
                    port: config.port,
                    voice: config.voice,
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
            pocketBinary: venvDirectory.appendingPathComponent("bin/pocket-tts"),
            logDirectory: logDirectory,
            logFile: logDirectory.appendingPathComponent("server.log")
        )
    }

    private func normalizedPath(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
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

    private func healthPayloadLooksHealthy(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? String else {
            return false
        }
        return status.lowercased() == "healthy"
    }

    private func pocketOpenAPIIsReachable(baseURL: String) async -> Bool {
        guard let url = URL(string: baseURL)?.appending(path: "openapi.json") else {
            return false
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                return false
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return false
            }
            let info = json["info"] as? [String: Any]
            let title = (info?["title"] as? String ?? "").lowercased()
            let paths = json["paths"] as? [String: Any]
            let hasTTSPath = paths?["/tts"] != nil
            return title.contains("pocket") && title.contains("tts") && hasTTSPath
        } catch {
            return false
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
