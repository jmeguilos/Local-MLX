import SwiftUI
import SwiftData

struct ConversationListView: View {
    @Binding var selectedConversation: Conversation?
    @Bindable var listViewModel: ConversationListViewModel

    @Query(sort: \Conversation.updatedAt, order: .reverse)
    private var conversations: [Conversation]

    @Environment(\.modelContext) private var modelContext

    private var filteredConversations: [Conversation] {
        if listViewModel.searchText.isEmpty {
            return conversations
        }
        return conversations.filter {
            $0.title.localizedCaseInsensitiveContains(listViewModel.searchText)
        }
    }

    var body: some View {
        List(selection: $selectedConversation) {
            ForEach(filteredConversations) { conversation in
                NavigationLink(value: conversation) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(conversation.title)
                            .font(.headline)
                            .lineLimit(1)
                        HStack {
                            Text(conversation.updatedAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !conversation.lastMessagePreview.isEmpty {
                                Text("- \(conversation.lastMessagePreview)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let conversation = filteredConversations[index]
                    if selectedConversation?.id == conversation.id {
                        selectedConversation = nil
                    }
                    listViewModel.deleteConversation(conversation)
                }
            }
        }
        .searchable(text: $listViewModel.searchText, prompt: "Search conversations")
        .navigationTitle("Conversations")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let config = try? modelContext.fetch(FetchDescriptor<ServerConfig>()).first
                    let conversation = listViewModel.createConversation(
                        systemPrompt: config?.defaultSystemPrompt
                    )
                    selectedConversation = conversation
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
}
