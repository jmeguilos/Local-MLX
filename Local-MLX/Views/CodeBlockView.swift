import SwiftUI

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

// MARK: - Content Parser

enum ContentSegment: Identifiable {
    case text(String)
    case codeBlock(language: String, code: String)

    var id: String {
        switch self {
        case .text(let s): return "text-\(s.hashValue)"
        case .codeBlock(let lang, let code): return "code-\(lang)-\(code.hashValue)"
        }
    }
}

enum ContentParser {
    static func parse(_ content: String) -> [ContentSegment] {
        var segments: [ContentSegment] = []

        let strippedContent = ThinkParser.parse(content).visible

        guard let regex = try? NSRegularExpression(pattern: "```(\\w*)\\n([\\s\\S]*?)```", options: []) else {
            return [.text(strippedContent)]
        }

        let nsContent = strippedContent as NSString
        var lastEnd = 0
        let matches = regex.matches(in: strippedContent, range: NSRange(location: 0, length: nsContent.length))

        for match in matches {
            let matchStart = match.range.location
            if matchStart > lastEnd {
                let before = nsContent.substring(with: NSRange(location: lastEnd, length: matchStart - lastEnd))
                if !before.isEmpty {
                    segments.append(.text(before))
                }
            }

            let language = match.numberOfRanges > 1 ? nsContent.substring(with: match.range(at: 1)) : ""
            let code = match.numberOfRanges > 2 ? nsContent.substring(with: match.range(at: 2)) : ""
            segments.append(.codeBlock(
                language: language.isEmpty ? "code" : language,
                code: code.hasSuffix("\n") ? String(code.dropLast()) : code
            ))

            lastEnd = match.range.location + match.range.length
        }

        if lastEnd < nsContent.length {
            segments.append(.text(nsContent.substring(from: lastEnd)))
        }

        return segments.isEmpty ? [.text(strippedContent)] : segments
    }
}

// MARK: - Code Block View

struct CodeBlockView: View {
    let language: String
    let code: String

    @State private var copied = false

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
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color.codeBlockBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.vertical, 4)
    }
}
