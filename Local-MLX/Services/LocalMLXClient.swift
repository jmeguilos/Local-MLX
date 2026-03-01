import Foundation
import MLX
import MLXLMCommon

struct LocalMLXClient: Sendable {
    let modelContainer: ModelContainer

    func streamChat(
        messages: [(role: String, content: String)],
        maxTokens: Int = 2048,
        temperature: Float = 0.7
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // Build Chat.Message array
                    let chatMessages: [Chat.Message] = messages.map { msg in
                        let role = Chat.Message.Role(rawValue: msg.role) ?? .user
                        return Chat.Message(role: role, content: msg.content)
                    }

                    let userInput = UserInput(chat: chatMessages)
                    let parameters = GenerateParameters(
                        maxTokens: maxTokens,
                        temperature: temperature
                    )

                    MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))

                    let lmInput = try await modelContainer.prepare(input: userInput)
                    let stream = try await modelContainer.generate(
                        input: lmInput,
                        parameters: parameters
                    )

                    for await generation in stream {
                        if Task.isCancelled { break }
                        if let chunk = generation.chunk, !chunk.isEmpty {
                            continuation.yield(chunk)
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
}
