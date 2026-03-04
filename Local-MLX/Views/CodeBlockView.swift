import SwiftUI
import HighlightSwift

// MARK: - Think Parser

struct ThinkParseResult {
    var visible: String
    var thinking: String
    var isCurrentlyInThink: Bool
    var thinkBlockFound: Bool
}

enum ThinkParser {
    static func parse(_ content: String) -> ThinkParseResult {
        var visible = ""
        var thinking = ""
        var inThink = false
        var thinkBlockFound = false

        var i = content.startIndex
        let openTag = "<think>"
        let closeTag = "</think>"

        while i < content.endIndex {
            if !inThink, content[i...].hasPrefix(openTag) {
                inThink = true
                thinkBlockFound = true
                i = content.index(i, offsetBy: openTag.count)
            } else if inThink, content[i...].hasPrefix(closeTag) {
                inThink = false
                i = content.index(i, offsetBy: closeTag.count)
            } else {
                if inThink {
                    thinking.append(content[i])
                } else {
                    visible.append(content[i])
                }
                i = content.index(after: i)
            }
        }

        return ThinkParseResult(
            visible: visible,
            thinking: thinking,
            isCurrentlyInThink: inThink,
            thinkBlockFound: thinkBlockFound
        )
    }
}

// MARK: - Code Block View (Enhanced with HighlightSwift)

struct CodeBlockView: View {
    let language: String
    let code: String

    @State private var copied = false
    @State private var highlightedCode: AttributedString?

    private var highlight: Highlight {
        Highlight()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(language)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    ClipboardHelper.copyText(code)
                    HapticManager.light()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                } label: {
                    Label(
                        copied ? "Copied" : "Copy",
                        systemImage: copied ? "checkmark" : "doc.on.doc"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.codeBlockHeader)

            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                if let highlighted = highlightedCode {
                    Text(highlighted)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(code)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(Color.codeBlockBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.vertical, 4)
        .task {
            await highlightCode()
        }
    }

    private func highlightCode() async {
        guard language != "code" else { return }
        do {
            let result = try await highlight.request(code, mode: .languageAlias(language))
            highlightedCode = result.attributedText
        } catch {
            // Fallback to plain text - already shown
        }
    }
}
