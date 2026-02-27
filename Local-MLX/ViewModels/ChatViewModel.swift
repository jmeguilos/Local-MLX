import Foundation
import SwiftData
import Observation

@Observable
final class ChatViewModel {
    var isGenerating = false
    var streamingContent = ""
    var errorMessage: String?

    private var streamTask: Task<Void, Never>?
    private var modelContext: ModelContext?

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func sendMessage(
        _ content: String,
        in conversation: Conversation,
        serverConfig: ServerConfig
    ) {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !isGenerating else { return }

        let userMessage = ChatMessage(role: .user, content: content, conversation: conversation)
        conversation.messages.append(userMessage)
        conversation.updatedAt = Date()

        if conversation.messages.count == 1 || conversation.title == "New Conversation" {
            conversation.title = String(content.prefix(40))
        }

        try? modelContext?.save()

        generateResponse(for: conversation, serverConfig: serverConfig)
    }

    func generateResponse(for conversation: Conversation, serverConfig: ServerConfig) {
        isGenerating = true
        streamingContent = ""
        errorMessage = nil

        let assistantMessage = ChatMessage(role: .assistant, content: "", conversation: conversation)
        conversation.messages.append(assistantMessage)

        let client = MLXServerClient(baseURL: serverConfig.baseURL)
        var apiMessages: [MLXServerClient.ChatRequest.Message] = []

        let systemPrompt = conversation.systemPrompt ?? serverConfig.defaultSystemPrompt
        if !systemPrompt.isEmpty {
            apiMessages.append(.init(role: "system", content: systemPrompt))
        }

        for msg in conversation.sortedMessages.dropLast() {
            apiMessages.append(.init(role: msg.role.rawValue, content: msg.content))
        }

        let model = serverConfig.defaultModel.isEmpty ? "default" : serverConfig.defaultModel

        streamTask = Task {
            do {
                let stream = client.streamChat(messages: apiMessages, model: model)
                for try await token in stream {
                    streamingContent += token
                    assistantMessage.content = streamingContent
                }
                try? modelContext?.save()
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                    if assistantMessage.content.isEmpty {
                        conversation.messages.removeAll { $0.id == assistantMessage.id }
                        modelContext?.delete(assistantMessage)
                    }
                }
            }
            isGenerating = false
            streamingContent = ""
            conversation.updatedAt = Date()
            try? modelContext?.save()
        }
    }

    func stopGenerating() {
        streamTask?.cancel()
        streamTask = nil
        isGenerating = false
    }

    func deleteMessage(_ message: ChatMessage, from conversation: Conversation) {
        conversation.messages.removeAll { $0.id == message.id }
        modelContext?.delete(message)
        try? modelContext?.save()
    }
}
