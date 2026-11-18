import XCTest
@testable import HibikiPocketRuntime

/// Drives the real manager against a fake `pocket-tts` binary that serves the health endpoints.
final class PocketRuntimeLifecycleTests: XCTestCase {
    private var venv: URL!

    private static let fakePocketServer = #"""
#!/usr/bin/python3
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

args = sys.argv[1:]
host = args[args.index('--host') + 1]
port = int(args[args.index('--port') + 1])

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

        try await manager.startServer(host: "127.0.0.1", port: port, voice: "alba", venvPath: venv.path)
        XCTAssertTrue(manager.isRunning)

        try await manager.restartServer(host: "127.0.0.1", port: port, voice: "alba", venvPath: venv.path)
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

        try await manager.startServer(host: "127.0.0.1", port: port, voice: "alba", venvPath: venv.path)
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
