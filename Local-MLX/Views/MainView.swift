import SwiftUI
import SwiftData

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedConversation: Conversation?
    @State private var chatViewModel = ChatViewModel()
    @State private var listViewModel = ConversationListViewModel()
    @State private var showSettings = false

    var body: some View {
        NavigationSplitView {
            ConversationListView(
                selectedConversation: $selectedConversation,
                listViewModel: listViewModel
            )
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
        } detail: {
            if let conversation = selectedConversation {
                ChatView(
                    conversation: conversation,
                    chatViewModel: chatViewModel
                )
            } else {
                ContentUnavailableView(
                    "No Conversation Selected",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Select or create a conversation to start chatting.")
                )
            }
        }
        .onAppear {
            chatViewModel.setModelContext(modelContext)
            listViewModel.setModelContext(modelContext)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}
