import Foundation
import SwiftData

@Model
final class Folder {
    var id: UUID
    var name: String
    var createdAt: Date

    @Relationship(inverse: \Conversation.folder)
    var conversations: [Conversation]

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.conversations = []
    }
}
