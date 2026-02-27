import SwiftUI
import SwiftData

struct ChatView: View {
    let conversation: Conversation
    var chatViewModel: ChatViewModel

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(conversation.sortedMessages) { message in
                            if message.role != .system {
                                MessageBubbleView(message: message)
                                    .id(message.id)
                                    .contextMenu {
                                        Button {
                                            ClipboardHelper.copyText(message.content)
                                        } label: {
                                            Label("Copy", systemImage: "doc.on.doc")
                                        }
                                        Button(role: .destructive) {
                                            chatViewModel.deleteMessage(message, from: conversation)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }

                        if chatViewModel.isGenerating {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 4)
                                Text("Generating...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal)
                            .id("typing-indicator")
                        }
                    }
                    .padding()
                }
                .onChange(of: conversation.sortedMessages.count) {
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: chatViewModel.streamingContent) {
                    scrollToBottom(proxy: proxy)
                }
            }

            Divider()

            MessageInputView(
                isGenerating: chatViewModel.isGenerating,
                onSend: { content in
                    let config = (try? modelContext.fetch(FetchDescriptor<ServerConfig>()).first)
                        ?? ServerConfig()
                    chatViewModel.sendMessage(content, in: conversation, serverConfig: config)
                },
                onStop: {
                    chatViewModel.stopGenerating()
                }
            )

            if let error = chatViewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Dismiss") {
                        chatViewModel.errorMessage = nil
                    }
                    .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(.red.opacity(0.1))
            }
        }
        .navigationTitle(conversation.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if chatViewModel.isGenerating {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("typing-indicator", anchor: .bottom)
            }
        } else if let lastMessage = conversation.sortedMessages.last {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
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
