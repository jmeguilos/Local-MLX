import Foundation
import SwiftData

enum MessageRole: String, Codable {
    case system
    case user
    case assistant
}

@Model
final class ChatMessage {
    var id: UUID
    var role: MessageRole
    var content: String
    var timestamp: Date
    var conversation: Conversation?
    var isEdited: Bool = false
    var promptTokens: Int?
    var completionTokens: Int?
    var imageAttachmentPaths: [String] = []

    init(role: MessageRole, content: String, conversation: Conversation? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.conversation = conversation
    }

    var totalTokens: Int? {
        guard let prompt = promptTokens, let completion = completionTokens else { return nil }
        return prompt + completion
    }
}
