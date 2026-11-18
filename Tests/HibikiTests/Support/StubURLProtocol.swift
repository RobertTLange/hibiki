import Foundation

/// Intercepts `URLSession.shared` requests to the cloud APIs so pipeline code can be
/// driven end to end without a network. Requests to other hosts pass through untouched.
final class StubURLProtocol: URLProtocol {
    struct Response {
        var status = 200
        var body = Data()
        var delay: TimeInterval = 0
    }

    private static let lock = NSLock()
    private static var handler: ((URLRequest) -> Response)?
    private static var recordedPaths: [String] = []

    static func install(_ handler: @escaping (URLRequest) -> Response) {
        lock.lock()
        self.handler = handler
        recordedPaths = []
        lock.unlock()
        URLProtocol.registerClass(StubURLProtocol.self)
    }

    static func uninstall() {
        URLProtocol.unregisterClass(StubURLProtocol.self)
        lock.lock()
        handler = nil
        lock.unlock()
    }

    static func requestCount(pathSuffix: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return recordedPaths.filter { $0.hasSuffix(pathSuffix) }.count
    }

    private let stateLock = NSLock()
    private var isStopped = false

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        lock.lock()
        defer { lock.unlock() }
        return handler != nil && ["api.openai.com", "api.elevenlabs.io"].contains(host)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.recordedPaths.append(request.url?.path ?? "")
        Self.lock.unlock()

        guard let handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let response = handler(request)
        DispatchQueue.global().asyncAfter(deadline: .now() + response.delay) { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            let stopped = self.isStopped
            self.stateLock.unlock()
            guard !stopped else { return }

            let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: nil)!
            self.client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: response.body)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        stateLock.lock()
        isStopped = true
        stateLock.unlock()
    }
}

enum StubResponses {
    /// An OpenAI chat-completions SSE stream that emits `sentences` one delta at a time.
    static func chatStream(sentences: [String], promptTokens: Int = 100, completionTokens: Int = 40) -> Data {
        var lines: [String] = []
        for sentence in sentences {
            let delta = ["choices": [["delta": ["content": sentence]]]]
            let json = String(data: try! JSONSerialization.data(withJSONObject: delta), encoding: .utf8)!
            lines.append("data: \(json)")
        }
        lines.append(#"data: {"choices":[],"usage":{"prompt_tokens":\#(promptTokens),"completion_tokens":\#(completionTokens)}}"#)
        lines.append("data: [DONE]")
        return Data((lines.joined(separator: "\n\n") + "\n\n").utf8)
    }

    /// 24kHz 16-bit mono silence.
    static func pcm(seconds: Double) -> Data {
        Data(count: Int(seconds * 24_000) * 2)
    }
}
