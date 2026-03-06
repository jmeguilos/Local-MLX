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
    var lastGenerationSpeed: Double? // tokens per second

    // Generation parameters (UI-controlled)
    var temperature: Double = 0.7
    var maxTokens: Int = 2048
    var showParameters: Bool = false

    // Message editing
    var editingMessageID: UUID?
    var editingText: String = ""

    private var streamTask: Task<Void, Never>?
    private var modelContext: ModelContext?

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func loadParametersFromConversation(_ conversation: Conversation) {
        if let temp = conversation.temperature {
            temperature = temp
        }
        if let tokens = conversation.maxTokens {
            maxTokens = tokens
        }
    }

    func saveParametersToConversation(_ conversation: Conversation) {
        conversation.temperature = temperature
        conversation.maxTokens = maxTokens
        try? modelContext?.save()
    }

    func sendMessage(
        _ content: String,
        in conversation: Conversation,
        serverConfig: ServerConfig,
        model: String? = nil,
        modelManager: ModelManager? = nil,
        imagePaths: [String] = []
    ) {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !isGenerating else { return }

        HapticManager.medium()

        // Check for /search command (F26)
        let (isSearch, query) = WebSearchService.isSearchRequest(content)
        if isSearch {
            let userMessage = ChatMessage(role: .user, content: content, conversation: conversation)
            conversation.messages.append(userMessage)
            conversation.updatedAt = Date()

            if conversation.messages.count == 1 || conversation.title == "New Conversation" {
                conversation.title = String(content.prefix(40))
            }
            try? modelContext?.save()

            performSearchAndRespond(query: query, in: conversation, serverConfig: serverConfig, model: model, modelManager: modelManager)
            return
        }

        let userMessage = ChatMessage(role: .user, content: content, conversation: conversation)
        if !imagePaths.isEmpty {
            userMessage.imageAttachmentPaths = imagePaths
        }
        conversation.messages.append(userMessage)
        conversation.updatedAt = Date()

        if conversation.messages.count == 1 || conversation.title == "New Conversation" {
            conversation.title = String(content.prefix(40))
        }
        try? modelContext?.save()

        generateResponse(for: conversation, serverConfig: serverConfig, model: model, modelManager: modelManager)
    }

    // MARK: - Web Search (F26)

    private func performSearchAndRespond(
        query: String,
        in conversation: Conversation,
        serverConfig: ServerConfig,
        model: String? = nil,
        modelManager: ModelManager? = nil
    ) {
        isGenerating = true
        errorMessage = nil

        streamTask = Task {
            do {
                let results = try await WebSearchService.search(query: query)
                let contextText = WebSearchService.formatForContext(results, query: query)

                // Insert search results as system message
                let searchMessage = ChatMessage(role: .system, content: contextText, conversation: conversation)
                conversation.messages.append(searchMessage)
                try? modelContext?.save()
            } catch {
                // Continue even if search fails
            }

            isGenerating = false

            // Now generate the response with search context included
            generateResponse(for: conversation, serverConfig: serverConfig, model: model, modelManager: modelManager)
        }
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
        lastGenerationSpeed = nil

        let generationStartTime = Date()
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

        let currentTemp = Float(temperature)
        let currentMaxTokens = maxTokens

        streamTask = Task {
            do {
                let stream: AsyncThrowingStream<String, Error>

                if serverConfig.isLocalMode, let container = modelManager?.modelContainer {
                    let localClient = LocalMLXClient(modelContainer: container)
                    stream = localClient.streamChat(
                        messages: chatMessages,
                        maxTokens: currentMaxTokens,
                        temperature: currentTemp
                    )
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
                    stream = client.streamChat(
                        messages: apiMessages,
                        model: resolvedModel,
                        temperature: currentTemp,
                        maxTokens: currentMaxTokens
                    )
                }

                var rawAccumulated = ""
                for try await token in stream {
                    // Check for usage metadata (F19)
                    if token.hasPrefix("[USAGE:") && token.hasSuffix("]") {
                        let inner = token.dropFirst(7).dropLast(1)
                        let parts = inner.split(separator: ",")
                        if parts.count == 2,
                           let prompt = Int(parts[0]),
                           let completion = Int(parts[1]) {
                            assistantMessage.promptTokens = prompt
                            assistantMessage.completionTokens = completion
                        }
                        continue
                    }

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
                // Calculate tokens/sec
                let elapsed = Date().timeIntervalSince(generationStartTime)
                if let completionTokens = assistantMessage.completionTokens, completionTokens > 0, elapsed > 0 {
                    lastGenerationSpeed = Double(completionTokens) / elapsed
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

    // MARK: - Message Editing (F13)

    func startEditing(message: ChatMessage) {
        editingMessageID = message.id
        editingText = message.content
    }

    func cancelEditing() {
        editingMessageID = nil
        editingText = ""
    }

    func submitEdit(
        for message: ChatMessage,
        in conversation: Conversation,
        serverConfig: ServerConfig,
        model: String? = nil,
        modelManager: ModelManager? = nil
    ) {
        let newContent = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newContent.isEmpty else { return }

        message.content = newContent
        message.isEdited = true

        // Remove all messages after this one
        let sorted = conversation.sortedMessages
        if let idx = sorted.firstIndex(where: { $0.id == message.id }) {
            let toRemove = sorted[(idx + 1)...]
            for msg in toRemove {
                conversation.messages.removeAll { $0.id == msg.id }
                modelContext?.delete(msg)
            }
        }

        try? modelContext?.save()
        cancelEditing()

        // Regenerate response
        generateResponse(for: conversation, serverConfig: serverConfig, model: model, modelManager: modelManager)
    }

    // MARK: - Conversation Branching (F25)

    func branchConversation(
        from message: ChatMessage,
        in conversation: Conversation
    ) -> Conversation? {
        let sorted = conversation.sortedMessages
        guard let idx = sorted.firstIndex(where: { $0.id == message.id }) else { return nil }

        let branch = Conversation(
            title: "\(conversation.title) (branch)",
            systemPrompt: conversation.systemPrompt
        )
        branch.temperature = conversation.temperature
        branch.maxTokens = conversation.maxTokens

        modelContext?.insert(branch)

        // Copy messages up to and including the selected message
        for msg in sorted[...idx] {
            let copy = ChatMessage(role: msg.role, content: msg.content, conversation: branch)
            copy.timestamp = msg.timestamp
            branch.messages.append(copy)
        }

        try? modelContext?.save()
        return branch
    }
}
