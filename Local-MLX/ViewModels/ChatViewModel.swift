import Foundation
import SwiftData
import Observation

@Observable
final class ChatViewModel {
    var isGenerating = false
    var streamingContent = ""
    var streamingThinking = ""
    var isInThinkBlock = false
    var thinkingStartTime: Date?
    var thinkingDuration: TimeInterval?
    var errorMessage: String?

    private var streamTask: Task<Void, Never>?
    private var modelContext: ModelContext?

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func sendMessage(
        _ content: String,
        in conversation: Conversation,
        serverConfig: ServerConfig,
        model: String? = nil,
        modelManager: ModelManager? = nil
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

        generateResponse(for: conversation, serverConfig: serverConfig, model: model, modelManager: modelManager)
    }

    func generateResponse(
        for conversation: Conversation,
        serverConfig: ServerConfig,
        model: String? = nil,
        modelManager: ModelManager? = nil
    ) {
        isGenerating = true
        streamingContent = ""
        streamingThinking = ""
        isInThinkBlock = false
        thinkingStartTime = nil
        thinkingDuration = nil
        errorMessage = nil

        let assistantMessage = ChatMessage(role: .assistant, content: "", conversation: conversation)
        conversation.messages.append(assistantMessage)

        // Build shared messages array
        var chatMessages: [(role: String, content: String)] = []
        let systemPrompt = conversation.systemPrompt ?? serverConfig.defaultSystemPrompt
        if !systemPrompt.isEmpty {
            chatMessages.append((role: "system", content: systemPrompt))
        }
        for msg in conversation.sortedMessages.dropLast() {
            chatMessages.append((role: msg.role.rawValue, content: msg.content))
        }

        streamTask = Task {
            do {
                let stream: AsyncThrowingStream<String, Error>

                if serverConfig.isLocalMode, let container = modelManager?.modelContainer {
                    let localClient = LocalMLXClient(modelContainer: container)
                    stream = localClient.streamChat(messages: chatMessages)
                } else {
                    let client = MLXServerClient(baseURL: serverConfig.baseURL)
                    let apiMessages = chatMessages.map {
                        MLXServerClient.ChatRequest.Message(role: $0.role, content: $0.content)
                    }
                    let resolvedModel: String
                    if let model, !model.isEmpty {
                        resolvedModel = model
                    } else {
                        resolvedModel = serverConfig.defaultModel.isEmpty ? "default" : serverConfig.defaultModel
                    }
                    stream = client.streamChat(messages: apiMessages, model: resolvedModel)
                }

                var rawAccumulated = ""
                for try await token in stream {
                    rawAccumulated += token
                    assistantMessage.content = rawAccumulated

                    let parsed = ThinkParser.parse(rawAccumulated)
                    streamingContent = parsed.visible
                    streamingThinking = parsed.thinking
                    isInThinkBlock = parsed.isCurrentlyInThink

                    if parsed.thinkBlockFound && thinkingStartTime == nil {
                        thinkingStartTime = Date()
                    }
                    if !parsed.isCurrentlyInThink && parsed.thinkBlockFound && thinkingDuration == nil {
                        thinkingDuration = Date().timeIntervalSince(thinkingStartTime ?? Date())
                    }
                }
                HapticManager.success()
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
            streamingThinking = ""
            isInThinkBlock = false
            conversation.updatedAt = Date()
            try? modelContext?.save()
        }
    }

    func regenerateLastResponse(
        in conversation: Conversation,
        serverConfig: ServerConfig,
        model: String? = nil,
        modelManager: ModelManager? = nil
    ) {
        guard !isGenerating else { return }

        // Find and remove the last assistant message
        if let lastAssistant = conversation.sortedMessages.last(where: { $0.role == .assistant }) {
            conversation.messages.removeAll { $0.id == lastAssistant.id }
            modelContext?.delete(lastAssistant)
            try? modelContext?.save()
        }

        generateResponse(for: conversation, serverConfig: serverConfig, model: model, modelManager: modelManager)
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
