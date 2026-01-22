import Foundation

enum TTSVoice: String, CaseIterable, Identifiable {
    case alloy, ash, ballad, coral, echo, fable, onyx, nova, sage, shimmer, verse
    var id: String { rawValue }
}

final class TTSService: NSObject {
    private var currentTask: URLSessionDataTask?
    private var session: URLSession?
    private var onAudioChunk: ((Data) -> Void)?
    private var onComplete: (() -> Void)?
    private var onError: ((Error) -> Void)?

    func streamSpeech(
        text: String,
        voice: TTSVoice,
        apiKey: String,
        instructions: String = "Speak naturally and clearly.",
        onAudioChunk: @escaping (Data) -> Void,
        onComplete: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        print("[Tyler] TTSService.streamSpeech called")
        print("[Tyler] Text length: \(text.count), voice: \(voice.rawValue)")

        self.onAudioChunk = onAudioChunk
        self.onComplete = onComplete
        self.onError = onError

        guard !apiKey.isEmpty else {
            print("[Tyler] ❌ API key is empty in TTSService")
            onError(TTSError.missingAPIKey)
            return
        }

        guard let url = URL(string: "https://api.openai.com/v1/audio/speech") else {
            print("[Tyler] ❌ Invalid URL")
            onError(TTSError.invalidURL)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini-tts",
            "input": text,
            "voice": voice.rawValue,
            "instructions": instructions,
            "response_format": "pcm"
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            print("[Tyler] ❌ JSON encoding error: \(error)")
            onError(error)
            return
        }

        print("[Tyler] 🌐 Making API request to OpenAI...")

        // Create session with delegate for streaming
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        currentTask = session?.dataTask(with: request)
        currentTask?.resume()
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        session?.invalidateAndCancel()
        session = nil
    }
}

extension TTSService: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        print("[Tyler] 📦 Received data chunk: \(data.count) bytes")
        onAudioChunk?(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            // Check if it's a cancellation
            if (error as NSError).code == NSURLErrorCancelled {
                print("[Tyler] Request cancelled")
                return
            }
            print("[Tyler] ❌ Network error: \(error.localizedDescription)")
            onError?(error)
        } else {
            print("[Tyler] ✅ Request completed successfully")
            onComplete?()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let httpResponse = response as? HTTPURLResponse {
            print("[Tyler] 📡 HTTP response: \(httpResponse.statusCode)")
            if httpResponse.statusCode != 200 {
                print("[Tyler] ❌ API error: HTTP \(httpResponse.statusCode)")
                onError?(TTSError.apiError(statusCode: httpResponse.statusCode))
                completionHandler(.cancel)
                return
            }
        }
        completionHandler(.allow)
    }
}

enum TTSError: Error, LocalizedError {
    case missingAPIKey
    case invalidURL
    case apiError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is not configured"
        case .invalidURL:
            return "Invalid API URL"
        case .apiError(let statusCode):
            return "API error: HTTP \(statusCode)"
        }
    }
}
