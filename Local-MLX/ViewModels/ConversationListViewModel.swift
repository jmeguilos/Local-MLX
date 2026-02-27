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
}
