import Foundation

struct StreamingParser: Sendable {
    struct ChatCompletionChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                var content: String?
                var role: String?
            }
            var delta: Delta
            var finish_reason: String?
        }
        var choices: [Choice]
    }

    nonisolated static func parseSSELine(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data: ") else { return nil }
        let jsonString = String(trimmed.dropFirst(6))
        if jsonString == "[DONE]" { return nil }

        guard let data = jsonString.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data),
              let content = chunk.choices.first?.delta.content else {
            return nil
        }
        return content
    }

    nonisolated static func isStreamDone(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines) == "data: [DONE]"
    }
}
