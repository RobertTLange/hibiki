import XCTest
@testable import HibikiPocketRuntime

/// Drives the real manager against a fake `pocket-tts` binary that serves the health endpoints.
/// The fake is strict about its arguments: the manager used to pass `serve --voice <name>`,
/// which pocket-tts 2.0 removed, so the real server exited with "No such option".
final class PocketRuntimeLifecycleTests: XCTestCase {
    private var venv: URL!

    private static let fakePocketServer = #"""
#!/usr/bin/python3
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

# Like the real CLI, refuse options it does not know.
args = sys.argv[1:]
if len(args) != 5 or args[0] != 'serve' or args[1] != '--host' or args[3] != '--port':
    sys.stderr.write("No such option in %r\n" % (args,))
    sys.exit(2)
host = args[2]
port = int(args[4])

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            body = {'status': 'healthy'}
        elif self.path == '/openapi.json':
            body = {'info': {'title': 'Kyutai Pocket TTS API'}, 'paths': {'/tts': {'post': {}}}}
        else:
            self.send_response(404)
            self.end_headers()
            return
        payload = json.dumps(body).encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, _format, *_args):
        return

HTTPServer((host, port), Handler).serve_forever()
"""#

    override func setUpWithError() throws {
        venv = FileManager.default.temporaryDirectory
            .appendingPathComponent("hibiki-lifecycle-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(".venv", isDirectory: true)
        let bin = venv.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let binary = bin.appendingPathComponent("pocket-tts")
        try Data(Self.fakePocketServer.utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    }

    override func tearDown() async throws {
        await MainActor.run { PocketTTSRuntimeManager.shared.stopServer() }
        try? FileManager.default.removeItem(at: venv.deletingLastPathComponent())
    }

    /// Regression: the old server's exit used to be attributed to its replacement, which was
    /// then dropped (and orphaned) while the restart reported a failure.
    @MainActor
    func testRestartKeepsTrackingTheReplacementServer() async throws {
        let manager = PocketTTSRuntimeManager.shared
        let port = try freeTCPPort()

        try await manager.startServer(host: "127.0.0.1", port: port, venvPath: venv.path)
        XCTAssertTrue(manager.isRunning)

        try await manager.restartServer(host: "127.0.0.1", port: port, venvPath: venv.path)
        XCTAssertTrue(manager.isRunning)

        // Give the first server's termination handler time to land.
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(manager.isRunning)
        XCTAssertEqual(manager.status, .running)
        let health = await manager.healthCheck(baseURL: PocketTTSRuntimeManager.baseURL(host: "127.0.0.1", port: port))
        XCTAssertTrue(health.isHealthy)
    }

    @MainActor
    func testStopServerReleasesThePort() async throws {
        let manager = PocketTTSRuntimeManager.shared
        let port = try freeTCPPort()
        let baseURL = PocketTTSRuntimeManager.baseURL(host: "127.0.0.1", port: port)

        try await manager.startServer(host: "127.0.0.1", port: port, venvPath: venv.path)
        manager.stopServer()

        XCTAssertFalse(manager.isRunning)
        XCTAssertEqual(manager.status, .stopped)

        var isDown = false
        for _ in 0..<40 where !isDown {
            isDown = await manager.healthCheck(baseURL: baseURL).statusCode == nil
            if !isDown {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        XCTAssertTrue(isDown, "server should be gone after stopServer()")
        // A deliberate stop is not a crash.
        XCTAssertEqual(manager.status, .stopped)
        XCTAssertNil(manager.lastError)
    }

    /// A server that dies at startup (port taken, bad install) must fail at once and be
    /// reported as such: callers try another port for this, but not for a slow start.
    @MainActor
    func testServerExitingDuringStartupFailsFastAndIsNotATimeout() async throws {
        let binary = venv.appendingPathComponent("bin/pocket-tts")
        try Data("#!/bin/sh\nexit 3\n".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)

        let manager = PocketTTSRuntimeManager.shared
        let started = Date()
        do {
            try await manager.startServer(host: "127.0.0.1", port: try freeTCPPort(), venvPath: venv.path, autoRestart: true)
            XCTFail("startServer should fail when the server exits")
        } catch PocketRuntimeError.startupFailed(let message) {
            XCTAssertTrue(message.contains("exited during startup"), message)
        }

        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
        XCTAssertFalse(manager.isRunning)
        XCTAssertEqual(manager.status, .failed)

        // No auto-restart loop for a server that never came up.
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertEqual(manager.status, .failed)
        XCTAssertFalse(manager.isRunning)
    }

    private func freeTCPPort() throws -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            "-c",
            "import socket; s=socket.socket(); s.bind(('127.0.0.1', 0)); print(s.getsockname()[1]); s.close()"
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let port = Int(text) else {
            throw NSError(domain: "PocketRuntimeLifecycleTests", code: 1)
        }
        return port
    }
}
