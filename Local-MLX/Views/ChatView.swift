import SwiftUI
import SwiftData

struct ChatView: View {
    let conversation: Conversation
    var chatViewModel: ChatViewModel
    var modelManager: ModelManager
    var onGoHome: (() -> Void)? = nil
    var onLocalModelChange: ((String) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @State private var showScrollToBottom = false
    @State private var contentHeight: CGFloat = 0
    @State private var scrollViewHeight: CGFloat = 0
    @State private var availableModels: [String] = []
    @State private var selectedModel: String = ""
    @State private var isNearBottom = true

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
            ZStack(alignment: .bottomTrailing) {
                if showEmptyState {
                    EmptyChatView(
                        onSuggestionTap: { suggestion in
                            sendMessage(suggestion)
                        },
                        modelManager: modelManager,
                        serverConfig: (try? modelContext.fetch(FetchDescriptor<ServerConfig>()).first) ?? ServerConfig()
                    )
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(visibleMessages) { message in
                                    let isLastAssistant = message.role == .assistant
                                        && message.id == visibleMessages.last(where: { $0.role == .assistant })?.id
                                    let isStreamingThis = chatViewModel.isGenerating
                                        && message.role == .assistant
                                        && message.id == conversation.sortedMessages.last?.id

                                    MessageRowView(
                                        message: message,
                                        isStreaming: isStreamingThis,
                                        isLastAssistantMessage: isLastAssistant && !chatViewModel.isGenerating,
                                        streamingThinking: isStreamingThis ? chatViewModel.streamingThinking : "",
                                        isInThinkBlock: isStreamingThis ? chatViewModel.isInThinkBlock : false,
                                        thinkingDuration: isStreamingThis ? chatViewModel.thinkingDuration : nil,
                                        onCopy: nil,
                                        onRegenerate: {
                                            regenerateResponse()
                                        }
                                    )
                                    .id(message.id)
                                    .frame(maxWidth: maxContentWidth)
                                    .frame(maxWidth: .infinity)
                                    .contextMenu {
                                        Button {
                                            ClipboardHelper.copyText(message.content)
                                        } label: {
                                            Label("Copy", systemImage: "doc.on.doc")
                                        }
                                        if message.role == .assistant && isLastAssistant && !chatViewModel.isGenerating {
                                            Button {
                                                regenerateResponse()
                                            } label: {
                                                Label("Regenerate", systemImage: "arrow.clockwise")
                                            }
                                        }
                                        Button(role: .destructive) {
                                            chatViewModel.deleteMessage(message, from: conversation)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }

                                Color.clear
                                    .frame(height: 1)
                                    .id("scroll-anchor")
                                    .onAppear { isNearBottom = true }
                                    .onDisappear { isNearBottom = false }
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
                    }
                }

                // Scroll-to-bottom button
                if showScrollToBottom && !showEmptyState {
                    Button {
                        showScrollToBottom = false
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
                serverConfig: (try? modelContext.fetch(FetchDescriptor<ServerConfig>()).first) ?? ServerConfig(),
                onSend: { content in
                    sendMessage(content)
                },
                onStop: {
                    chatViewModel.stopGenerating()
                },
                onModelChange: { model in
                    selectedModel = model
                },
                onLocalModelChange: onLocalModelChange
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
        }
        .task {
            let config = (try? modelContext.fetch(FetchDescriptor<ServerConfig>()).first) ?? ServerConfig()
            if !config.isLocalMode {
                await fetchModels()
            }
        }
    }

    // MARK: - Helpers

    private func sendMessage(_ content: String) {
        let config = (try? modelContext.fetch(FetchDescriptor<ServerConfig>()).first)
            ?? ServerConfig()

        if config.isLocalMode && modelManager.modelState != .loaded {
            chatViewModel.errorMessage = "Local model not loaded"
            return
        }

        let model = selectedModel.isEmpty ? nil : selectedModel
        chatViewModel.sendMessage(
            content, in: conversation, serverConfig: config,
            model: model, modelManager: modelManager
        )
    }

    private func regenerateResponse() {
        let config = (try? modelContext.fetch(FetchDescriptor<ServerConfig>()).first)
            ?? ServerConfig()

        if config.isLocalMode && modelManager.modelState != .loaded {
            chatViewModel.errorMessage = "Local model not loaded"
            return
        }

        let model = selectedModel.isEmpty ? nil : selectedModel
        chatViewModel.regenerateLastResponse(
            in: conversation, serverConfig: config,
            model: model, modelManager: modelManager
        )
    }

    private func fetchModels() async {
        let config = (try? modelContext.fetch(FetchDescriptor<ServerConfig>()).first) ?? ServerConfig()
        let client = MLXServerClient(baseURL: config.baseURL)
        do {
            let models = try await client.fetchModels()
            availableModels = models
            if selectedModel.isEmpty {
                selectedModel = config.defaultModel.isEmpty
                    ? (models.first ?? "")
                    : config.defaultModel
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
