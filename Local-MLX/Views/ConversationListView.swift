import SwiftUI
import SwiftData

struct ConversationListView: View {
    @Binding var selectedConversation: Conversation?
    @Bindable var listViewModel: ConversationListViewModel
    var modelManager: ModelManager
    var config: ServerConfig
    var onNewChat: (String) -> Void
    var onSettingsTap: () -> Void = {}

    @Query(sort: \Conversation.updatedAt, order: .reverse)
    private var conversations: [Conversation]

    @Query(sort: \Folder.name)
    private var folders: [Folder]

    @Environment(\.modelContext) private var modelContext

    @State private var renamingConversation: Conversation?
    @State private var renameText: String = ""
    @State private var newChatText = ""
    @FocusState private var isInputFocused: Bool

    @State private var showArchived = false
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var moveToFolderConversation: Conversation?

    private var filteredConversations: [Conversation] {
        let active = conversations.filter { !$0.isArchived }
        if listViewModel.searchText.isEmpty {
            return active
        }
        return active.filter {
            $0.title.localizedCaseInsensitiveContains(listViewModel.searchText)
        }
    }

    private var archivedConversations: [Conversation] {
        conversations.filter { $0.isArchived }
    }

    private var unfolderedConversations: [Conversation] {
        filteredConversations.filter { $0.folder == nil }
    }

    private var groupedConversations: [(String, [Conversation])] {
        let calendar = Calendar.current
        let now = Date()
        let convos = unfolderedConversations

        var today: [Conversation] = []
        var yesterday: [Conversation] = []
        var previous7Days: [Conversation] = []
        var previous30Days: [Conversation] = []
        var older: [Conversation] = []

        for conversation in convos {
            let date = conversation.updatedAt
            if calendar.isDateInToday(date) {
                today.append(conversation)
            } else if calendar.isDateInYesterday(date) {
                yesterday.append(conversation)
            } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now),
                      date >= weekAgo {
                previous7Days.append(conversation)
            } else if let monthAgo = calendar.date(byAdding: .day, value: -30, to: now),
                      date >= monthAgo {
                previous30Days.append(conversation)
            } else {
                older.append(conversation)
            }
        }

        var groups: [(String, [Conversation])] = []
        if !today.isEmpty { groups.append(("Today", today)) }
        if !yesterday.isEmpty { groups.append(("Yesterday", yesterday)) }
        if !previous7Days.isEmpty { groups.append(("Previous 7 Days", previous7Days)) }
        if !previous30Days.isEmpty { groups.append(("Previous 30 Days", previous30Days)) }
        if !older.isEmpty { groups.append(("Older", older)) }
        return groups
    }

    var body: some View {
        List(selection: $selectedConversation) {
            #if os(iOS)
            Section {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 20))
                            .foregroundStyle(.purple.gradient)
                        Text("Local MLX")
                            .font(.headline)
                    }

                    ModelStatusChip(modelManager: modelManager, config: config)

                    HStack(spacing: 8) {
                        TextField("Ask anything...", text: $newChatText)
                            .textFieldStyle(.plain)
                            .focused($isInputFocused)
                            .onSubmit { sendInlineMessage() }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)

                        Button(action: sendInlineMessage) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(
                                    newChatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        ? Color.secondary.opacity(0.4)
                                        : Color.accentColor
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(newChatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .padding(.trailing, 4)
                    }
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            #endif

            // Folder sections (F12)
            ForEach(folders) { folder in
                Section {
                    DisclosureGroup {
                        let folderConvos = filteredConversations.filter { $0.folder?.id == folder.id }
                            .sorted { $0.updatedAt > $1.updatedAt }
                        ForEach(folderConvos) { conversation in
                            NavigationLink(value: conversation) {
                                conversationRow(conversation)
                            }
                            .contextMenu {
                                conversationContextMenu(conversation, inFolder: true)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                                .font(.caption)
                            Text(folder.name)
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }

            // Unfoldered conversations grouped by time
            ForEach(groupedConversations, id: \.0) { group, convos in
                Section {
                    ForEach(convos) { conversation in
                        NavigationLink(value: conversation) {
                            conversationRow(conversation)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                if selectedConversation?.id == conversation.id {
                                    selectedConversation = nil
                                }
                                listViewModel.deleteConversation(conversation)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                if selectedConversation?.id == conversation.id {
                                    selectedConversation = nil
                                }
                                listViewModel.archiveConversation(conversation)
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                            .tint(.blue)
                        }
                        .contextMenu {
                            conversationContextMenu(conversation, inFolder: false)
                        }
                    }
                } header: {
                    Text(group)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }

            // Archived section
            if !archivedConversations.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showArchived) {
                        ForEach(archivedConversations) { conversation in
                            NavigationLink(value: conversation) {
                                conversationRow(conversation)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    if selectedConversation?.id == conversation.id {
                                        selectedConversation = nil
                                    }
                                    listViewModel.deleteConversation(conversation)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    listViewModel.unarchiveConversation(conversation)
                                } label: {
                                    Label("Unarchive", systemImage: "tray.and.arrow.up")
                                }
                                .tint(.green)
                            }
                            .contextMenu {
                                Button {
                                    listViewModel.unarchiveConversation(conversation)
                                } label: {
                                    Label("Unarchive", systemImage: "tray.and.arrow.up")
                                }
                                Button(role: .destructive) {
                                    if selectedConversation?.id == conversation.id {
                                        selectedConversation = nil
                                    }
                                    listViewModel.deleteConversation(conversation)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } label: {
                        Label("Archived", systemImage: "archivebox")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $listViewModel.searchText, prompt: "Search")
        .navigationTitle("Chats")
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    onSettingsTap()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gear")
                            .font(.subheadline)
                        Text("Settings")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    showNewFolderAlert = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
            .background(.ultraThinMaterial)
        }
        .alert("Rename Conversation", isPresented: .init(
            get: { renamingConversation != nil },
            set: { if !$0 { renamingConversation = nil } }
        )) {
            TextField("Conversation name", text: $renameText)
            Button("Cancel", role: .cancel) {
                renamingConversation = nil
            }
            Button("Rename") {
                if let conversation = renamingConversation {
                    listViewModel.renameConversation(conversation, to: renameText)
                }
                renamingConversation = nil
            }
        }
        .alert("New Folder", isPresented: $showNewFolderAlert) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) {
                newFolderName = ""
            }
            Button("Create") {
                let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                let folder = Folder(name: trimmed)
                modelContext.insert(folder)
                try? modelContext.save()
                newFolderName = ""
            }
        }
        .confirmationDialog("Move to Folder", isPresented: .init(
            get: { moveToFolderConversation != nil },
            set: { if !$0 { moveToFolderConversation = nil } }
        )) {
            Button("None (Remove from folder)") {
                moveToFolderConversation?.folder = nil
                try? modelContext.save()
                moveToFolderConversation = nil
            }
            ForEach(folders) { folder in
                Button(folder.name) {
                    moveToFolderConversation?.folder = folder
                    try? modelContext.save()
                    moveToFolderConversation = nil
                }
            }
            Button("Cancel", role: .cancel) {
                moveToFolderConversation = nil
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func conversationContextMenu(_ conversation: Conversation, inFolder: Bool) -> some View {
        Button {
            renameText = conversation.title
            renamingConversation = conversation
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button {
            moveToFolderConversation = conversation
        } label: {
            Label("Move to Folder…", systemImage: "folder")
        }

        // Export submenu (F11)
        Menu {
            Button {
                ExportHelper.exportMarkdown(conversation: conversation)
            } label: {
                Label("Markdown", systemImage: "doc.text")
            }
            Button {
                ExportHelper.exportJSON(conversation: conversation)
            } label: {
                Label("JSON", systemImage: "curlybraces")
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }

        Button {
            if selectedConversation?.id == conversation.id {
                selectedConversation = nil
            }
            listViewModel.archiveConversation(conversation)
        } label: {
            Label("Archive", systemImage: "archivebox")
        }

        Button(role: .destructive) {
            if selectedConversation?.id == conversation.id {
                selectedConversation = nil
            }
            listViewModel.deleteConversation(conversation)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func sendInlineMessage() {
        let text = newChatText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        newChatText = ""
        isInputFocused = false
        onNewChat(text)
    }

    private func conversationRow(_ conversation: Conversation) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(conversation.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)

            if !conversation.lastMessagePreview.isEmpty {
                Text(conversation.lastMessagePreview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
