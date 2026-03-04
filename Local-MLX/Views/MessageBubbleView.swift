import SwiftUI
import SwiftData

struct MessageRowView: View {
    let message: ChatMessage
    let isStreaming: Bool
    let isLastAssistantMessage: Bool
    var streamingThinking: String = ""
    var isInThinkBlock: Bool = false
    var thinkingDuration: TimeInterval? = nil
    var isEdited: Bool = false
    let onCopy: (() -> Void)?
    let onRegenerate: (() -> Void)?
    var onEdit: ((String) -> Void)? = nil

    init(
        message: ChatMessage,
        isStreaming: Bool = false,
        isLastAssistantMessage: Bool = false,
        streamingThinking: String = "",
        isInThinkBlock: Bool = false,
        thinkingDuration: TimeInterval? = nil,
        isEdited: Bool = false,
        onCopy: (() -> Void)? = nil,
        onRegenerate: (() -> Void)? = nil,
        onEdit: ((String) -> Void)? = nil
    ) {
        self.message = message
        self.isStreaming = isStreaming
        self.isLastAssistantMessage = isLastAssistantMessage
        self.streamingThinking = streamingThinking
        self.isInThinkBlock = isInThinkBlock
        self.thinkingDuration = thinkingDuration
        self.isEdited = isEdited
        self.onCopy = onCopy
        self.onRegenerate = onRegenerate
        self.onEdit = onEdit
    }

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatarView
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(isUser ? "You" : "Assistant")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    if isEdited {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                if !isUser {
                    assistantContent
                        .animation(.easeInOut(duration: 0.2), value: isStreaming)
                } else {
                    userContent
                }

                if !isUser && !isStreaming && !message.content.isEmpty {
                    HStack {
                        actionBar

                        // Token usage badge (F19)
                        if let tokens = message.totalTokens {
                            Text("\(tokens) tokens")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 8)
                        }
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3).delay(0.1), value: isStreaming)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isUser ? Color.userMessageBackground : Color.clear)
    }

    // MARK: - User Content

    @ViewBuilder
    private var userContent: some View {
        // Image attachments (F18)
        if !message.imageAttachmentPaths.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(message.imageAttachmentPaths, id: \.self) { path in
                        if let data = FileManager.default.contents(atPath: path) {
                            #if os(macOS)
                            if let nsImage = NSImage(data: data) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            #else
                            if let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            #endif
                        }
                    }
                }
            }
            .padding(.bottom, 4)
        }

        Text(markdownInline(message.content))
            .font(.body)
            .textSelection(.enabled)
            .lineSpacing(3)
    }

    // MARK: - Assistant Content

    @ViewBuilder
    private var assistantContent: some View {
        if isStreaming && message.content.isEmpty {
            thinkingIndicator
                .transition(.opacity)
        } else if isStreaming && isInThinkBlock {
            ThinkBlockView(
                thinking: streamingThinking,
                isStreaming: true,
                duration: nil
            )
            .transition(.opacity)
        } else if isStreaming {
            let parsed = ThinkParser.parse(message.content)
            Group {
                if parsed.thinkBlockFound {
                    ThinkBlockView(
                        thinking: streamingThinking,
                        isStreaming: false,
                        duration: thinkingDuration
                    )
                }

                // During streaming, use lightweight regex parser
                let segments = ContentParser.parseStreaming(parsed.visible)
                ForEach(segments) { segment in
                    streamingSegmentView(segment)
                }

                BlinkingCursor()
            }
            .transition(.opacity)
        } else {
            let parsed = ThinkParser.parse(message.content)
            Group {
                if parsed.thinkBlockFound {
                    ThinkBlockView(
                        thinking: parsed.thinking,
                        isStreaming: false,
                        duration: nil
                    )
                }
                renderedContent
            }
            .transition(.opacity)
        }
    }

    // MARK: - Rendered Content with Rich Blocks

    @ViewBuilder
    private var renderedContent: some View {
        let segments = ContentParser.parse(message.content)
        ForEach(segments) { segment in
            richSegmentView(segment)
        }
    }

    @ViewBuilder
    private func richSegmentView(_ segment: ContentSegment) -> some View {
        switch segment {
        case .text(let text):
            Text(markdownInline(text))
                .font(.body)
                .textSelection(.enabled)
                .lineSpacing(3)
        case .codeBlock(let language, let code):
            CodeBlockView(language: language, code: code)
        case .heading(let level, let text):
            HeadingView(level: level, text: text)
        case .blockquote(let text):
            BlockquoteView(text: text)
        case .orderedList(let items):
            OrderedListView(items: items)
        case .unorderedList(let items):
            UnorderedListView(items: items)
        case .table(let headers, let rows):
            TableBlockView(headers: headers, rows: rows)
        case .latex(let latex):
            LaTeXBlockView(latex: latex)
        case .mermaid(let code):
            MermaidBlockView(code: code)
        case .thematicBreak:
            ThematicBreakView()
        }
    }

    @ViewBuilder
    private func streamingSegmentView(_ segment: ContentSegment) -> some View {
        switch segment {
        case .text(let text):
            Text(markdownInline(text))
                .font(.body)
                .textSelection(.enabled)
                .lineSpacing(3)
        case .codeBlock(let language, let code):
            CodeBlockView(language: language, code: code)
        case .mermaid(let code):
            // During streaming, show mermaid as code block
            CodeBlockView(language: "mermaid", code: code)
        default:
            // During streaming, render other blocks as simple text
            if case .heading(_, let text) = segment {
                Text(markdownInline(text))
                    .font(.body)
                    .fontWeight(.bold)
                    .textSelection(.enabled)
            } else {
                EmptyView()
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                ClipboardHelper.copyText(message.content)
                HapticManager.light()
                onCopy?()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if isLastAssistantMessage {
                Button {
                    onRegenerate?()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Avatar

    @ViewBuilder
    private var avatarView: some View {
        if isUser {
            Circle()
                .fill(Color.accentColor.gradient)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
        } else {
            Circle()
                .fill(Color.assistantAvatarBackground)
                .overlay {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.purple)
                }
        }
    }

    // MARK: - Thinking Indicator

    private var thinkingIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.subheadline)
                .foregroundStyle(.purple)
                .symbolEffect(.pulse)

            Text("Thinking...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Blinking Cursor

struct BlinkingCursor: View {
    @State private var visible = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.accentColor)
            .frame(width: 2, height: 16)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}

// MARK: - Think Block View

struct ThinkBlockView: View {
    let thinking: String
    let isStreaming: Bool
    let duration: TimeInterval?

    @State private var isExpanded = false

    private var label: String {
        if isStreaming {
            return "Thinking..."
        } else if let duration {
            return "Thought for \(Int(duration))s"
        } else {
            return "View thinking"
        }
    }

    private var icon: String {
        isStreaming ? "sparkles" : "brain"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    if isStreaming {
                        Image(systemName: icon)
                            .font(.caption)
                            .foregroundStyle(.purple)
                            .symbolEffect(.pulse)
                    } else {
                        Image(systemName: icon)
                            .font(.caption)
                            .foregroundStyle(.purple)
                    }

                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)

            if isExpanded && !thinking.isEmpty {
                Text(thinking)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineSpacing(2)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.codeBlockBackground, in: RoundedRectangle(cornerRadius: 8))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Colors

extension Color {
    static var userMessageBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor).opacity(0.5)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }

    static var assistantAvatarBackground: Color {
        #if os(macOS)
        Color.purple.opacity(0.12)
        #else
        Color.purple.opacity(0.12)
        #endif
    }

    static var inputFieldBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }

    static var inputFieldBorder: Color {
        #if os(macOS)
        Color(nsColor: .separatorColor)
        #else
        Color(uiColor: .separator)
        #endif
    }

    static var surfaceBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }

    static var codeBlockBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor).opacity(0.6)
        #else
        Color(uiColor: .tertiarySystemBackground)
        #endif
    }

    static var codeBlockHeader: Color {
        #if os(macOS)
        Color(nsColor: .separatorColor).opacity(0.3)
        #else
        Color(uiColor: .quaternarySystemFill)
        #endif
    }
}
