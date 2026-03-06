import SwiftUI
import SwiftData

struct ChatView: View {
    let conversation: Conversation
    @Bindable var chatViewModel: ChatViewModel
    var modelManager: ModelManager
    var onGoHome: (() -> Void)? = nil
    var onLocalModelChange: ((String) -> Void)? = nil
    var onBranch: ((Conversation) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Query private var serverConfigs: [ServerConfig]
    @State private var showScrollToBottom = false
    @State private var availableModels: [String] = []
    @State private var selectedModel: String = ""
    @State private var isNearBottom = true
    @State private var showSystemPromptEditor = false
    @State private var pendingImages: [Data] = []
    @State private var exportErrorMessage: String?

    private var currentConfig: ServerConfig {
        serverConfigs.first ?? ServerConfig()
    }

    private var maxContentWidth: CGFloat {
        #if os(macOS)
        720
        #else
        .infinity
        #endif
    }

    private var visibleMessages: [ChatMessage] {
        conversation.sortedMessages.filter { $0.role != .system }
    }

    private var showEmptyState: Bool {
        visibleMessages.isEmpty && !chatViewModel.isGenerating
    }

    var body: some View {
        VStack(spacing: 0) {
            // Parameter controls (F10)
            if chatViewModel.showParameters {
                parameterControls
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            ZStack(alignment: .bottomTrailing) {
                if showEmptyState {
                    EmptyChatView(
                        onSuggestionTap: { suggestion in
                            sendMessage(suggestion)
                        },
                        modelManager: modelManager,
                        serverConfig: currentConfig
                    )
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(visibleMessages) { message in
                                    messageCell(for: message)
                                }

                                Color.clear
                                    .frame(height: 1)
                                    .id("scroll-anchor")
                                    .onAppear {
                                        isNearBottom = true
                                        showScrollToBottom = false
                                    }
                                    .onDisappear {
                                        isNearBottom = false
                                        showScrollToBottom = true
                                    }
                            }
                            .padding(.vertical, 8)
                            .animation(.easeOut(duration: 0.25), value: visibleMessages.count)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: conversation.sortedMessages.count) {
                            scrollToBottom(proxy: proxy, animated: true)
                        }
                        .onChange(of: chatViewModel.streamingContent) {
                            if isNearBottom {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    proxy.scrollTo("scroll-anchor", anchor: .bottom)
                                }
                            }
                        }
                        .onAppear {
                            scrollToBottom(proxy: proxy, animated: false)
                        }
                        .overlay(alignment: .bottomTrailing) {
                            // Scroll-to-bottom button
                            if showScrollToBottom {
                                Button {
                                    scrollToBottom(proxy: proxy, animated: true)
                                } label: {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.title2)
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(.secondary)
                                        .background(Circle().fill(Color.surfaceBackground).padding(2))
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, 16)
                                .padding(.bottom, 8)
                                .transition(.opacity.combined(with: .scale))
                            }
                        }
                    }
                }
            }

            // Model loading banner
            if currentConfig.isLocalMode && modelManager.modelState == .loading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading model…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.codeBlockBackground)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Error banner
            if let error = chatViewModel.errorMessage {
                errorBanner(error)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.25), value: chatViewModel.errorMessage)
            }

            // Input
            MessageInputView(
                isGenerating: chatViewModel.isGenerating,
                currentModel: selectedModel,
                availableModels: availableModels,
                modelManager: modelManager,
                serverConfig: currentConfig,
                onSend: { content in
                    sendMessage(content)
                },
                onStop: {
                    chatViewModel.stopGenerating()
                },
                onModelChange: { model in
                    selectedModel = model
                },
                onLocalModelChange: onLocalModelChange,
                onToggleParameters: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        chatViewModel.showParameters.toggle()
                    }
                },
                onImageAttach: { images in
                    pendingImages = images
                }
            )
        }
        .navigationTitle(conversation.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    onGoHome?()
                } label: {
                    Image(systemName: "house")
                }
                .help("Home")
            }

            #if os(macOS)
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarActions
            }
            #else
            ToolbarItemGroup(placement: .topBarTrailing) {
                toolbarActions
            }
            #endif
        }
        // Keyboard shortcuts (F15) — copy last assistant message
        .background {
            Group {
                Button("") {
                    if let lastAssistant = visibleMessages.last(where: { $0.role == .assistant }) {
                        ClipboardHelper.copyText(lastAssistant.content)
                    }
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .hidden()
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        }
        .sheet(isPresented: $showSystemPromptEditor) {
            SystemPromptEditorView(conversation: conversation)
        }
        .alert("Export Failed", isPresented: .init(
            get: { exportErrorMessage != nil },
            set: { if !$0 { exportErrorMessage = nil } }
        )) {
            Button("OK") { exportErrorMessage = nil }
        } message: {
            if let error = exportErrorMessage {
                Text(error)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportError)) { notification in
            if let error = notification.userInfo?["error"] as? String {
                exportErrorMessage = error
            }
        }
        .task {
            chatViewModel.loadParametersFromConversation(conversation)
            if !currentConfig.isLocalMode {
                await fetchModels()
            }
        }
    }

    // MARK: - Toolbar Actions

    @ViewBuilder
    private var toolbarActions: some View {
        Button {
            showSystemPromptEditor = true
        } label: {
            Image(systemName: "text.bubble")
        }
        .help("System Prompt")

        Menu {
            Button {
                if let error = ExportHelper.exportMarkdown(conversation: conversation) {
                    exportErrorMessage = error
                }
            } label: {
                Label("Export as Markdown", systemImage: "doc.text")
            }
            Button {
                if let error = ExportHelper.exportJSON(conversation: conversation) {
                    exportErrorMessage = error
                }
            } label: {
                Label("Export as JSON", systemImage: "curlybraces")
            }
            Button {
                if let error = ExportHelper.exportPlainText(conversation: conversation) {
                    exportErrorMessage = error
                }
            } label: {
                Label("Export as Plain Text", systemImage: "doc.plaintext")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .help("Export")
    }

    // MARK: - Parameter Controls (F10)

    private var parameterControls: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Generation Parameters")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Temperature: \(chatViewModel.temperature, specifier: "%.2f")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $chatViewModel.temperature, in: 0.0...2.0, step: 0.05)
                        .frame(maxWidth: 200)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Max Tokens: \(chatViewModel.maxTokens)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Stepper("", value: $chatViewModel.maxTokens, in: 256...8192, step: 256)
                        .labelsHidden()
                }

                Spacer()

                Button("Save to Chat") {
                    chatViewModel.saveParametersToConversation(conversation)
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.codeBlockBackground)
    }

    // MARK: - Message Cell

    @ViewBuilder
    private func messageCell(for message: ChatMessage) -> some View {
        let lastAssistantID = visibleMessages.last(where: { $0.role == .assistant })?.id
        let isLastAssistant = message.role == .assistant && message.id == lastAssistantID
        let isStreamingThis = chatViewModel.isGenerating
            && message.role == .assistant
            && message.id == conversation.sortedMessages.last?.id

        if chatViewModel.editingMessageID == message.id && message.role == .user {
            editingMessageView(message: message)
                .id(message.id)
                .frame(maxWidth: maxContentWidth)
                .frame(maxWidth: .infinity)
        } else {
            messageRowWithContext(message: message, isLastAssistant: isLastAssistant, isStreamingThis: isStreamingThis)
                .id(message.id)
                .frame(maxWidth: maxContentWidth)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func messageRowWithContext(message: ChatMessage, isLastAssistant: Bool, isStreamingThis: Bool) -> some View {
        MessageRowView(
            message: message,
            isStreaming: isStreamingThis,
            isLastAssistantMessage: isLastAssistant && !chatViewModel.isGenerating,
            streamingThinking: isStreamingThis ? chatViewModel.streamingThinking : "",
            isInThinkBlock: isStreamingThis ? chatViewModel.isInThinkBlock : false,
            thinkingDuration: isStreamingThis ? chatViewModel.thinkingDuration : nil,
            isEdited: message.isEdited,
            generationSpeed: (isLastAssistant && !chatViewModel.isGenerating) ? chatViewModel.lastGenerationSpeed : nil,
            onCopy: nil,
            onRegenerate: {
                regenerateResponse()
            }
        )
        .contextMenu {
            Button {
                ClipboardHelper.copyText(message.content)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            if message.role == .user && !chatViewModel.isGenerating {
                Button {
                    chatViewModel.startEditing(message: message)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
            if message.role == .assistant && isLastAssistant && !chatViewModel.isGenerating {
                Button {
                    regenerateResponse()
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
            }
            Button {
                branchFromMessage(message)
            } label: {
                Label("Branch from here", systemImage: "arrow.triangle.branch")
            }
            Button(role: .destructive) {
                chatViewModel.deleteMessage(message, from: conversation)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Editing View (F13)

    private func editingMessageView(message: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color.accentColor.gradient)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 8) {
                Text("Editing message")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                TextEditor(text: $chatViewModel.editingText)
                    .font(.body)
                    .frame(minHeight: 60, maxHeight: 200)
                    .padding(8)
                    .background(Color.inputFieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 1))

                HStack {
                    Button("Cancel") {
                        chatViewModel.cancelEditing()
                    }
                    .buttonStyle(.bordered)

                    Button("Submit") {
                        let model = selectedModel.isEmpty ? nil : selectedModel
                        chatViewModel.submitEdit(
                            for: message,
                            in: conversation,
                            serverConfig: currentConfig,
                            model: model,
                            modelManager: modelManager
                        )
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.userMessageBackground)
    }

    // MARK: - Helpers

    private func sendMessage(_ content: String) {
        if currentConfig.isLocalMode && modelManager.modelState != .loaded {
            chatViewModel.errorMessage = "Local model not loaded"
            return
        }

        // Save any pending image attachments (F18)
        var imagePaths: [String] = []
        if !pendingImages.isEmpty {
            imagePaths = saveImages(pendingImages)
            pendingImages = []
        }

        let model = selectedModel.isEmpty ? nil : selectedModel
        chatViewModel.sendMessage(
            content, in: conversation, serverConfig: currentConfig,
            model: model, modelManager: modelManager,
            imagePaths: imagePaths
        )
    }

    private func saveImages(_ images: [Data]) -> [String] {
        var paths: [String] = []
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("local-mlx-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for imageData in images {
            let filename = UUID().uuidString + ".jpg"
            let url = dir.appendingPathComponent(filename)
            try? imageData.write(to: url)
            paths.append(url.path)
        }
        return paths
    }

    private func regenerateResponse() {
        if currentConfig.isLocalMode && modelManager.modelState != .loaded {
            chatViewModel.errorMessage = "Local model not loaded"
            return
        }

        let model = selectedModel.isEmpty ? nil : selectedModel
        chatViewModel.regenerateLastResponse(
            in: conversation, serverConfig: currentConfig,
            model: model, modelManager: modelManager
        )
    }

    private func branchFromMessage(_ message: ChatMessage) {
        if let branch = chatViewModel.branchConversation(from: message, in: conversation) {
            onBranch?(branch)
        }
    }

    private func fetchModels() async {
        let client = MLXServerClient(baseURL: currentConfig.baseURL)
        do {
            let models = try await client.fetchModels()
            availableModels = models
            if selectedModel.isEmpty {
                selectedModel = currentConfig.defaultModel.isEmpty
                    ? (models.first ?? "")
                    : currentConfig.defaultModel
            }
        } catch {
            // Models will just be empty — user can still type
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        let target = "scroll-anchor"

        if animated {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(target, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.subheadline)
            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button {
                chatViewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.08))
    }
}

// MARK: - System Prompt Editor (F16)

struct SystemPromptEditorView: View {
    let conversation: Conversation
    @Environment(\.dismiss) private var dismiss
    @State private var systemPrompt: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("System prompt for this conversation. Changes take effect on the next message.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextEditor(text: $systemPrompt)
                    .font(.body)
                    .frame(minHeight: 150)
                    .padding(8)
                    .background(Color.inputFieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Spacer()
            }
            .padding()
            .navigationTitle("System Prompt")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        conversation.systemPrompt = systemPrompt.isEmpty ? nil : systemPrompt
                        dismiss()
                    }
                }
            }
            .onAppear {
                systemPrompt = conversation.systemPrompt ?? ""
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }
}

// Cross-platform pasteboard helper
enum ClipboardHelper {
    static func copyText(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}
