import XCTest
@testable import HibikiPocketRuntime

final class PocketRuntimeHealthTests: XCTestCase {
    private var processes: [Process] = []

    override func tearDown() {
        for process in processes where process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        processes.removeAll()
        super.tearDown()
    }

    func testHealthCheckRejectsNonPocketServer() async throws {
        let port = try freeTCPPort()
        _ = try launchProcess(
            executable: "/usr/bin/python3",
            arguments: ["-m", "http.server", String(port)]
        )

        try await waitUntilReachable(url: URL(string: "http://127.0.0.1:\(port)/")!)

        let health = await PocketTTSRuntimeManager.shared.healthCheck(
            baseURL: "http://127.0.0.1:\(port)"
        )

        XCTAssertFalse(health.isHealthy)
        XCTAssertFalse(health.isPocketAPI)
        XCTAssertEqual(health.statusCode, 404)
    }

    func testHealthCheckAcceptsPocketCompatibleServer() async throws {
        let port = try freeTCPPort()
        let script = #"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

port = int(sys.argv[1])

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            payload = json.dumps({'status': 'healthy'}).encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return

        if self.path == '/openapi.json':
            payload = json.dumps({
                'openapi': '3.1.0',
                'info': {'title': 'Kyutai Pocket TTS API'},
                'paths': {'/tts': {'post': {}}},
            }).encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return

        self.send_response(404)
        self.end_headers()

    def log_message(self, _format, *_args):
        return

HTTPServer(('127.0.0.1', port), Handler).serve_forever()
"""#

        _ = try launchProcess(
            executable: "/usr/bin/python3",
            arguments: ["-c", script, String(port)]
        )

        try await waitUntilReachable(url: URL(string: "http://127.0.0.1:\(port)/health")!)

        let health = await PocketTTSRuntimeManager.shared.healthCheck(
            baseURL: "http://127.0.0.1:\(port)"
        )

        XCTAssertTrue(health.isHealthy)
        XCTAssertTrue(health.isPocketAPI)
        XCTAssertEqual(health.statusCode, 200)
        XCTAssertNil(health.message)
    }

    private func launchProcess(executable: String, arguments: [String]) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        processes.append(process)
        return process
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
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0,
              let text,
              let port = Int(text),
              (1025...65535).contains(port) else {
            throw NSError(domain: "PocketRuntimeHealthTests", code: 1)
        }

        return port
    }

    private func waitUntilReachable(url: URL, timeout: TimeInterval = 6.0) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        var lastError: Error?

        while Date() < deadline {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 0.5
                _ = try await URLSession.shared.data(for: request)
                return
            } catch {
                lastError = error
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        throw lastError ?? NSError(domain: "PocketRuntimeHealthTests", code: 2)
    }
}
