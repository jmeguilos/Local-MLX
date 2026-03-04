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
        struct Usage: Decodable {
            var prompt_tokens: Int?
            var completion_tokens: Int?
            var total_tokens: Int?
        }
        var choices: [Choice]
        var usage: Usage?
    }

    struct TokenUsage: Sendable {
        var promptTokens: Int
        var completionTokens: Int
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

    /// Parse token usage from SSE line (often in the final chunk)
    nonisolated static func parseUsage(_ line: String) -> TokenUsage? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data: ") else { return nil }
        let jsonString = String(trimmed.dropFirst(6))
        guard jsonString != "[DONE]",
              let data = jsonString.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data),
              let usage = chunk.usage,
              let prompt = usage.prompt_tokens,
              let completion = usage.completion_tokens else {
            return nil
        }
        return TokenUsage(promptTokens: prompt, completionTokens: completion)
    }
}
