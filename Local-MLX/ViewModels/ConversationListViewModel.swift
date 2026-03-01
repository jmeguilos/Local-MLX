import Foundation
import SwiftData
import Observation

@Observable
final class ConversationListViewModel {
    var searchText = ""

    private var modelContext: ModelContext?

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    @discardableResult
    func createConversation(systemPrompt: String? = nil) -> Conversation {
        let conversation = Conversation(systemPrompt: systemPrompt)
        modelContext?.insert(conversation)
        try? modelContext?.save()
        return conversation
    }

    func deleteConversation(_ conversation: Conversation) {
        modelContext?.delete(conversation)
        try? modelContext?.save()
    }

    func renameConversation(_ conversation: Conversation, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        conversation.title = trimmed
        conversation.updatedAt = Date()
        try? modelContext?.save()
    }

    func archiveConversation(_ conversation: Conversation) {
        conversation.isArchived = true
        try? modelContext?.save()
    }

    func unarchiveConversation(_ conversation: Conversation) {
        conversation.isArchived = false
        try? modelContext?.save()
    }
}
