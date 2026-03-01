import Foundation

struct MLXServerClient: Sendable {
    struct ModelsResponse: Decodable {
        struct Model: Decodable {
            var id: String
        }
        var data: [Model]
    }

    struct ChatRequest: Encodable {
        var model: String
        var messages: [Message]
        var stream: Bool = true
        var max_tokens: Int = 2048
        var temperature: Double = 0.7

        struct Message: Encodable {
            var role: String
            var content: String
        }
    }

    let baseURL: String

    init(baseURL: String = "http://localhost:8080") {
        var url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip trailing slashes
        while url.hasSuffix("/") {
            url.removeLast()
        }
        // Strip trailing /v1 so users can paste either form
        if url.hasSuffix("/v1") {
            url = String(url.dropLast(3))
        }
        self.baseURL = url
    }

    private nonisolated func makeURL(_ path: String) throws -> URL {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw ServerError.invalidURL
        }
        return url
    }

    nonisolated func fetchModels() async throws -> [String] {
        let url = try makeURL("/v1/models")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ServerError.invalidResponse
        }
        let modelsResponse = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return modelsResponse.data.map(\.id)
    }

    nonisolated func streamChat(
        messages: [ChatRequest.Message],
        model: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = try makeURL("/v1/chat/completions")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    let chatRequest = ChatRequest(
                        model: model,
                        messages: messages
                    )
                    request.httpBody = try JSONEncoder().encode(chatRequest)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        throw ServerError.invalidResponse
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        if StreamingParser.isStreamDone(line) { break }
                        if let token = StreamingParser.parseSSELine(line) {
                            continuation.yield(token)
                        }
                    }
                    continuation.finish()
                } catch {
                    if !Task.isCancelled {
                        continuation.finish(throwing: error)
                    } else {
                        continuation.finish()
                    }
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    nonisolated func chat(
        messages: [ChatRequest.Message],
        model: String,
        maxTokens: Int = 512
    ) async throws -> String {
        let url = try makeURL("/v1/chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var chatRequest = ChatRequest(model: model, messages: messages)
        chatRequest.stream = false
        chatRequest.max_tokens = maxTokens
        request.httpBody = try JSONEncoder().encode(chatRequest)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ServerError.invalidResponse
        }

        struct ChatCompletion: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    var content: String
                }
                var message: Message
            }
            var choices: [Choice]
        }

        let completion = try JSONDecoder().decode(ChatCompletion.self, from: data)
        return completion.choices.first?.message.content ?? ""
    }

    nonisolated func checkConnection() async -> (Bool, String?) {
        do {
            let url = try makeURL("/v1/models")
            let (_, response) = try await URLSession.shared.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 {
                return (true, nil)
            } else {
                return (false, "HTTP \(status)")
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }

    enum ServerError: LocalizedError {
        case invalidResponse
        case invalidURL
        case connectionFailed

        var errorDescription: String? {
            switch self {
            case .invalidResponse: "Invalid response from server"
            case .invalidURL: "Invalid server URL"
            case .connectionFailed: "Could not connect to server"
            }
        }
    }
}
