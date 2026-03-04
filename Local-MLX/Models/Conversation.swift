import Foundation
import SwiftData

@Model
final class Conversation {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var systemPrompt: String?
    var isArchived: Bool = false
    var temperature: Double?
    var maxTokens: Int?
    var folder: Folder?

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.conversation)
    var messages: [ChatMessage]

    init(title: String = "New Conversation", systemPrompt: String? = nil) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.systemPrompt = systemPrompt
        self.messages = []
    }

    var sortedMessages: [ChatMessage] {
        messages.sorted { $0.timestamp < $1.timestamp }
    }

    var lastMessagePreview: String {
        let lastUserMessage = sortedMessages.last(where: { $0.role == .user })
        return lastUserMessage?.content.prefix(80).description ?? ""
    }
}
