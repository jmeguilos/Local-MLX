import SwiftUI
import SwiftData

struct MainView: View {
    var modelManager: ModelManager

    @Environment(\.modelContext) private var modelContext
    @Query private var configs: [ServerConfig]
    @State private var selectedConversation: Conversation?
    @State private var chatViewModel = ChatViewModel()
    @State private var listViewModel = ConversationListViewModel()
    @State private var showSettings = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    private var currentConfig: ServerConfig {
        configs.first ?? ServerConfig()
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ConversationListView(
                selectedConversation: $selectedConversation,
                listViewModel: listViewModel,
                modelManager: modelManager,
                config: currentConfig,
                onNewChat: { message in
                    createConversationWithMessage(message)
                },
                onSettingsTap: {
                    showSettings = true
                }
            )
        } detail: {
            if let conversation = selectedConversation {
                ChatView(
                    conversation: conversation,
                    chatViewModel: chatViewModel,
                    modelManager: modelManager,
                    onGoHome: { selectedConversation = nil },
                    onLocalModelChange: { newModelID in
                        if let config = configs.first {
                            config.localModelID = newModelID
                            try? modelContext.save()
                        }
                    },
                    onBranch: { branch in
                        selectedConversation = branch
                    }
                )
            } else {
                WelcomeView(
                    modelManager: modelManager,
                    config: currentConfig,
                    onSend: { message in
                        createConversationWithMessage(message)
                    },
                    onPersonaSelect: { persona in
                        let conversation = listViewModel.createConversationFromPersona(persona)
                        selectedConversation = conversation
                    }
                )
            }
        }
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    createNewConversation()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .fontWeight(.medium)
                }
                .help("New Chat")
            }
            #else
            ToolbarItem(placement: .navigation) {
                Button {
                    createNewConversation()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .fontWeight(.medium)
                }
                .help("New Chat")
            }
            #endif
        }
        .onAppear {
            chatViewModel.setModelContext(modelContext)
            listViewModel.setModelContext(modelContext)
            autoLoadLocalModelIfNeeded()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(modelManager: modelManager)
        }
        // Keyboard Shortcuts (F15) — handled via hidden buttons
        .background {
            Group {
                Button("") { createNewConversation() }
                    .keyboardShortcut("n", modifiers: .command)
                    .hidden()
                Button("") { showSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
                    .hidden()
                Button("") { selectedConversation = nil }
                    .keyboardShortcut("w", modifiers: .command)
                    .hidden()
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        }
    }

    @discardableResult
    private func createNewConversation() -> Conversation {
        let config = try? modelContext.fetch(FetchDescriptor<ServerConfig>()).first
        let conversation = listViewModel.createConversation(
            systemPrompt: config?.defaultSystemPrompt
        )
        selectedConversation = conversation
        return conversation
    }

    private func autoLoadLocalModelIfNeeded() {
        let config = (try? modelContext.fetch(FetchDescriptor<ServerConfig>()).first) ?? ServerConfig()
        guard config.isLocalMode else { return }

        switch modelManager.modelState {
        case .notDownloaded:
            modelManager.checkCachedModel(modelID: config.localModelID)
            if modelManager.modelState == .ready {
                modelManager.loadModel(modelID: config.localModelID)
            }
        case .ready:
            modelManager.loadModel(modelID: config.localModelID)
        default:
            break
        }
    }

    private func createConversationWithMessage(_ message: String) {
        let conversation = createNewConversation()
        let config = (try? modelContext.fetch(FetchDescriptor<ServerConfig>()).first) ?? ServerConfig()
        chatViewModel.sendMessage(message, in: conversation, serverConfig: config, modelManager: modelManager)
    }
}

// MARK: - Suggestion Generator

enum SuggestionGenerator {
    static let fallbackSuggestions: [(icon: String, text: String)] = [
        ("pencil.and.outline", "Write a short story about a robot discovering nature"),
        ("atom", "Explain quantum computing in simple terms"),
        ("chevron.left.forwardslash.chevron.right", "Write a Python function to sort a list"),
        ("map", "Plan a weekend trip to a nearby city"),
    ]

    private static let dynamicIcons = ["lightbulb", "brain", "book", "globe"]

    static func generateSuggestions(config: ServerConfig, modelManager: ModelManager) async -> [(icon: String, text: String)] {
        let prompt = "Generate 4 short conversation starters as a JSON array of strings. Each should be a single sentence, diverse in topic. Return ONLY the JSON array, no other text."
        let messages: [(role: String, content: String)] = [
            (role: "user", content: prompt)
        ]

        do {
            let responseText: String
            if config.isLocalMode {
                guard case .loaded = modelManager.modelState,
                      let container = modelManager.modelContainer else {
                    return fallbackSuggestions
                }
                let client = LocalMLXClient(modelContainer: container)
                var collected = ""
                for try await token in client.streamChat(messages: messages, maxTokens: 256, temperature: 0.9) {
                    collected += token
                }
                responseText = collected
            } else {
                let client = MLXServerClient(baseURL: config.baseURL)
                let model = config.defaultModel.isEmpty ? (try? await client.fetchModels().first) ?? "" : config.defaultModel
                let serverMessages = messages.map { MLXServerClient.ChatRequest.Message(role: $0.role, content: $0.content) }
                responseText = try await client.chat(messages: serverMessages, model: model, maxTokens: 256)
            }

            // Parse JSON array from response
            if let jsonStart = responseText.firstIndex(of: "["),
               let jsonEnd = responseText.lastIndex(of: "]") {
                let jsonStr = String(responseText[jsonStart...jsonEnd])
                if let data = jsonStr.data(using: .utf8),
                   let array = try? JSONDecoder().decode([String].self, from: data),
                   array.count >= 4 {
                    return array.prefix(4).enumerated().map { index, text in
                        (icon: dynamicIcons[index % dynamicIcons.count], text: text)
                    }
                }
            }
        } catch {
            // Fall through to fallback
        }

        return fallbackSuggestions
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    let modelManager: ModelManager
    let config: ServerConfig
    let onSend: (String) -> Void
    var onPersonaSelect: ((Persona) -> Void)? = nil

    @Query(sort: \Persona.name) private var personas: [Persona]
    @State private var inputText = ""
    @State private var dynamicSuggestions: [(icon: String, text: String)] = SuggestionGenerator.fallbackSuggestions
    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.purple.gradient)

            Text("Local MLX")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Chat with local language models")
                .font(.title3)
                .foregroundStyle(.secondary)

            // Input field
            welcomeInputField
                .frame(maxWidth: 520)
                .padding(.horizontal, 24)

            // Model status
            ModelStatusChip(modelManager: modelManager, config: config)
                .padding(.top, -8)

            // Persona quick-select (F17)
            if !personas.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(personas) { persona in
                            Button {
                                onPersonaSelect?(persona)
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: persona.icon)
                                        .font(.title3)
                                        .foregroundStyle(.purple)
                                    Text(persona.name)
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                                .frame(width: 72, height: 60)
                                .background(Color.userMessageBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .frame(maxWidth: 520)
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
            ], spacing: 12) {
                ForEach(dynamicSuggestions, id: \.text) { suggestion in
                    Button {
                        onSend(suggestion.text)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: suggestion.icon)
                                .font(.subheadline)
                                .foregroundStyle(.purple)
                                .frame(width: 22)

                            Text(suggestion.text)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.userMessageBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 24)
            .padding(.top, 8)

            Spacer()

            Text("Connect to a server or download a local model to get started")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            let results = await SuggestionGenerator.generateSuggestions(config: config, modelManager: modelManager)
            dynamicSuggestions = results
        }
    }

    private var welcomeInputField: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask anything...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused($isFocused)
                .onSubmit {
                    #if os(macOS)
                    sendWelcomeMessage()
                    #endif
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            Button(action: sendWelcomeMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .padding(.trailing, 6)
            .padding(.bottom, 6)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func sendWelcomeMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        HapticManager.medium()
        onSend(text)
    }
}

// MARK: - Model Status Chip

struct ModelStatusChip: View {
    let modelManager: ModelManager
    let config: ServerConfig

    private var shortModelName: String {
        let id = config.localModelID
        if let lastSlash = id.lastIndex(of: "/") {
            return String(id[id.index(after: lastSlash)...])
        }
        return id
    }

    var body: some View {
        HStack(spacing: 5) {
            if config.isLocalMode {
                switch modelManager.modelState {
                case .loaded:
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text(shortModelName)
                case .loading:
                    ProgressView()
                        .controlSize(.mini)
                    Text("Loading model...")
                case .downloading(let progress):
                    ProgressView()
                        .controlSize(.mini)
                    Text("Downloading \(Int(progress * 100))%...")
                default:
                    Circle()
                        .fill(.orange)
                        .frame(width: 6, height: 6)
                    Text("No model loaded")
                }
            } else {
                Image(systemName: "server.rack")
                    .font(.system(size: 9))
                Text(config.defaultModel.isEmpty ? "Server mode" : config.defaultModel)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
