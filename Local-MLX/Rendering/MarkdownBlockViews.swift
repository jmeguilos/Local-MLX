import SwiftUI

// MARK: - Heading View

struct HeadingView: View {
    let level: Int
    let text: String

    private var font: Font {
        switch level {
        case 1: return .title
        case 2: return .title2
        case 3: return .title3
        case 4: return .headline
        case 5: return .subheadline
        default: return .subheadline
        }
    }

    private var weight: Font.Weight {
        level <= 3 ? .bold : .semibold
    }

    var body: some View {
        Text(markdownInline(text))
            .font(font)
            .fontWeight(weight)
            .textSelection(.enabled)
            .padding(.top, level <= 2 ? 8 : 4)
            .padding(.bottom, 2)
    }
}

// MARK: - Blockquote View

struct BlockquoteView: View {
    let text: String

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.purple.opacity(0.6))
                .frame(width: 3)

            Text(markdownInline(text))
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineSpacing(2)
                .padding(.leading, 12)
                .padding(.vertical, 4)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Unordered List View

struct UnorderedListView: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\u{2022}")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text(markdownInline(item))
                        .font(.body)
                        .textSelection(.enabled)
                        .lineSpacing(2)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.leading, 4)
    }
}

// MARK: - Ordered List View

struct OrderedListView: View {
    let items: [(index: Int, text: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(item.index).")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(minWidth: 20, alignment: .trailing)
                    Text(markdownInline(item.text))
                        .font(.body)
                        .textSelection(.enabled)
                        .lineSpacing(2)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.leading, 4)
    }
}

// MARK: - Table View

struct TableBlockView: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                // Header row
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        Text(header)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(Color.codeBlockHeader)

                Divider()

                // Data rows
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(markdownInline(cell))
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                    .background(rowIdx.isMultiple(of: 2) ? Color.clear : Color.codeBlockBackground.opacity(0.5))
                }
            }
        }
        .background(Color.codeBlockBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.vertical, 4)
    }
}

// MARK: - Thematic Break

struct ThematicBreakView: View {
    var body: some View {
        Divider()
            .padding(.vertical, 8)
    }
}

// MARK: - Inline Markdown Helper

func markdownInline(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
}
