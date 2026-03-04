import Foundation
import Markdown

// MARK: - Extended Content Segment

enum ContentSegment: Identifiable {
    case text(String)
    case codeBlock(language: String, code: String)
    case heading(level: Int, text: String)
    case blockquote(String)
    case orderedList([(index: Int, text: String)])
    case unorderedList([String])
    case table(headers: [String], rows: [[String]])
    case latex(String)
    case mermaid(String)
    case thematicBreak

    var id: String {
        switch self {
        case .text(let s): return "text-\(s.hashValue)"
        case .codeBlock(let lang, let code): return "code-\(lang)-\(code.hashValue)"
        case .heading(let level, let text): return "h\(level)-\(text.hashValue)"
        case .blockquote(let s): return "bq-\(s.hashValue)"
        case .orderedList(let items): return "ol-\(items.map(\.text).joined().hashValue)"
        case .unorderedList(let items): return "ul-\(items.joined().hashValue)"
        case .table(let h, let r): return "table-\(h.joined().hashValue)-\(r.count)"
        case .latex(let s): return "latex-\(s.hashValue)"
        case .mermaid(let s): return "mermaid-\(s.hashValue)"
        case .thematicBreak: return "hr-\(UUID().uuidString)"
        }
    }
}

// MARK: - Markdown Renderer (swift-markdown based)

enum MarkdownRenderer {

    /// Full parse using swift-markdown for completed content
    static func parse(_ content: String) -> [ContentSegment] {
        let stripped = ThinkParser.parse(content).visible.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return [] }

        // Pre-process: extract LaTeX blocks before markdown parsing
        let (processed, latexBlocks) = extractLatexBlocks(stripped)

        let document = Document(parsing: processed, options: [.parseBlockDirectives, .parseSymbolLinks])
        var visitor = BlockVisitor(latexBlocks: latexBlocks)
        visitor.visit(document)

        let segments = visitor.segments
        return segments.isEmpty ? [.text(stripped)] : segments
    }

    /// Lightweight regex parse for streaming content (fast, partial-safe)
    static func parseStreaming(_ content: String) -> [ContentSegment] {
        let stripped = ThinkParser.parse(content).visible
        guard !stripped.isEmpty else { return [] }
        return regexParse(stripped)
    }

    // MARK: - LaTeX Pre-processing

    private static func extractLatexBlocks(_ content: String) -> (String, [String: String]) {
        var result = content
        var blocks: [String: String] = [:]

        // Display math: $$...$$ (multiline)
        let displayPattern = try? NSRegularExpression(pattern: "\\$\\$([\\s\\S]*?)\\$\\$", options: [])
        if let matches = displayPattern?.matches(in: result, range: NSRange(result.startIndex..., in: result)) {
            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: result),
                      let innerRange = Range(match.range(at: 1), in: result) else { continue }
                let latex = String(result[innerRange])
                let placeholder = "LATEX_PLACEHOLDER_\(blocks.count)"
                blocks[placeholder] = latex
                result.replaceSubrange(fullRange, with: placeholder)
            }
        }

        // \[...\] display math
        let bracketPattern = try? NSRegularExpression(pattern: "\\\\\\[([\\s\\S]*?)\\\\\\]", options: [])
        if let matches = bracketPattern?.matches(in: result, range: NSRange(result.startIndex..., in: result)) {
            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: result),
                      let innerRange = Range(match.range(at: 1), in: result) else { continue }
                let latex = String(result[innerRange])
                let placeholder = "LATEX_PLACEHOLDER_\(blocks.count)"
                blocks[placeholder] = latex
                result.replaceSubrange(fullRange, with: placeholder)
            }
        }

        return (result, blocks)
    }

    // MARK: - Regex Fallback Parser (for streaming)

    private static func regexParse(_ content: String) -> [ContentSegment] {
        var segments: [ContentSegment] = []

        guard let regex = try? NSRegularExpression(pattern: "```(\\w*)\\n([\\s\\S]*?)```", options: []) else {
            return [.text(content)]
        }

        let nsContent = content as NSString
        var lastEnd = 0
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))

        for match in matches {
            let matchStart = match.range.location
            if matchStart > lastEnd {
                let before = nsContent.substring(with: NSRange(location: lastEnd, length: matchStart - lastEnd))
                if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(.text(before))
                }
            }

            let language = match.numberOfRanges > 1 ? nsContent.substring(with: match.range(at: 1)) : ""
            let code = match.numberOfRanges > 2 ? nsContent.substring(with: match.range(at: 2)) : ""

            if language.lowercased() == "mermaid" {
                segments.append(.mermaid(code.hasSuffix("\n") ? String(code.dropLast()) : code))
            } else {
                segments.append(.codeBlock(
                    language: language.isEmpty ? "code" : language,
                    code: code.hasSuffix("\n") ? String(code.dropLast()) : code
                ))
            }

            lastEnd = match.range.location + match.range.length
        }

        if lastEnd < nsContent.length {
            let remaining = nsContent.substring(from: lastEnd)
            if !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.text(remaining))
            }
        }

        return segments.isEmpty ? [.text(content)] : segments
    }
}

// MARK: - swift-markdown Block Visitor

private struct BlockVisitor: MarkupWalker {
    var segments: [ContentSegment] = []
    let latexBlocks: [String: String]

    init(latexBlocks: [String: String] = [:]) {
        self.latexBlocks = latexBlocks
    }

    mutating func visitDocument(_ document: Document) {
        for child in document.children {
            visitBlock(child)
        }
    }

    private mutating func visitBlock(_ markup: any Markup) {
        if let heading = markup as? Heading {
            let text = heading.plainText
            segments.append(.heading(level: heading.level, text: text))
        } else if let codeBlock = markup as? CodeBlock {
            let language = codeBlock.language ?? "code"
            let code = codeBlock.code.hasSuffix("\n") ? String(codeBlock.code.dropLast()) : codeBlock.code
            if language.lowercased() == "mermaid" {
                segments.append(.mermaid(code))
            } else {
                segments.append(.codeBlock(language: language, code: code))
            }
        } else if let blockquote = markup as? BlockQuote {
            let text = blockquote.plainText
            segments.append(.blockquote(text))
        } else if let orderedList = markup as? OrderedList {
            var items: [(index: Int, text: String)] = []
            for (idx, item) in orderedList.listItems.enumerated() {
                items.append((index: idx + 1, text: item.plainText))
            }
            segments.append(.orderedList(items))
        } else if let unorderedList = markup as? UnorderedList {
            var items: [String] = []
            for item in unorderedList.listItems {
                items.append(item.plainText)
            }
            segments.append(.unorderedList(items))
        } else if let table = markup as? Markdown.Table {
            var headers: [String] = []
            for cell in table.head.cells {
                headers.append(cell.plainText)
            }
            var rows: [[String]] = []
            for row in table.body.rows {
                var rowData: [String] = []
                for cell in row.cells {
                    rowData.append(cell.plainText)
                }
                rows.append(rowData)
            }
            segments.append(.table(headers: headers, rows: rows))
        } else if markup is ThematicBreak {
            segments.append(.thematicBreak)
        } else if let paragraph = markup as? Paragraph {
            let text = paragraph.format()
            // Check for latex placeholders
            for (placeholder, latex) in latexBlocks {
                if text.contains(placeholder) {
                    segments.append(.latex(latex))
                    return
                }
            }
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.text(text))
            }
        } else if let htmlBlock = markup as? HTMLBlock {
            let text = htmlBlock.rawHTML
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.text(text))
            }
        } else {
            // Fallback: recurse into children
            for child in markup.children {
                visitBlock(child)
            }
        }
    }
}

// MARK: - Markup Helpers

private extension Markup {
    var plainText: String {
        var result = ""
        for child in children {
            if let text = child as? Markdown.Text {
                result += text.string
            } else if child is SoftBreak {
                result += " "
            } else if child is LineBreak {
                result += "\n"
            } else if let code = child as? InlineCode {
                result += "`\(code.code)`"
            } else if let emphasis = child as? Emphasis {
                result += emphasis.plainText
            } else if let strong = child as? Strong {
                result += strong.plainText
            } else if let link = child as? Markdown.Link {
                result += "[\(link.plainText)](\(link.destination ?? ""))"
            } else if let image = child as? Markdown.Image {
                result += "![\(image.plainText)](\(image.source ?? ""))"
            } else if let strikethrough = child as? Strikethrough {
                result += "~~\(strikethrough.plainText)~~"
            } else {
                result += child.plainText
            }
        }
        return result
    }
}

// MARK: - ContentParser (updated to use MarkdownRenderer)

enum ContentParser {
    static func parse(_ content: String) -> [ContentSegment] {
        MarkdownRenderer.parse(content)
    }

    static func parseStreaming(_ content: String) -> [ContentSegment] {
        MarkdownRenderer.parseStreaming(content)
    }
}
