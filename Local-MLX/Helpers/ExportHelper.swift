import Foundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum ExportHelper {

    // MARK: - Markdown Export

    static func exportMarkdown(conversation: Conversation) {
        let markdown = generateMarkdown(conversation: conversation)
        let filename = sanitizeFilename(conversation.title) + ".md"
        saveFile(content: markdown, filename: filename, contentType: "text/markdown")
    }

    static func generateMarkdown(conversation: Conversation) -> String {
        var lines: [String] = []
        lines.append("# \(conversation.title)")
        lines.append("")
        lines.append("*Exported from Local MLX on \(formattedDate(Date()))*")
        lines.append("")

        if let systemPrompt = conversation.systemPrompt, !systemPrompt.isEmpty {
            lines.append("---")
            lines.append("**System Prompt:** \(systemPrompt)")
            lines.append("---")
            lines.append("")
        }

        for message in conversation.sortedMessages {
            switch message.role {
            case .system:
                continue
            case .user:
                lines.append("### User")
                lines.append("")
                lines.append(message.content)
                lines.append("")
            case .assistant:
                lines.append("### Assistant")
                lines.append("")
                let parsed = ThinkParser.parse(message.content)
                if parsed.thinkBlockFound {
                    lines.append("<details>")
                    lines.append("<summary>Thinking</summary>")
                    lines.append("")
                    lines.append(parsed.thinking)
                    lines.append("")
                    lines.append("</details>")
                    lines.append("")
                }
                lines.append(parsed.visible)
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - JSON Export

    static func exportJSON(conversation: Conversation) {
        let json = generateJSON(conversation: conversation)
        let filename = sanitizeFilename(conversation.title) + ".json"
        saveFile(content: json, filename: filename, contentType: "application/json")
    }

    static func generateJSON(conversation: Conversation) -> String {
        struct MessageExport: Encodable {
            let role: String
            let content: String
            let timestamp: String
        }

        let formatter = ISO8601DateFormatter()
        let messages = conversation.sortedMessages.map { msg in
            MessageExport(
                role: msg.role.rawValue,
                content: msg.content,
                timestamp: formatter.string(from: msg.timestamp)
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(messages),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    // MARK: - Helpers

    private static func sanitizeFilename(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "[^a-zA-Z0-9\\-_ ]", with: "", options: .regularExpression)
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "conversation" : String(trimmed.prefix(50))
    }

    private static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func saveFile(content: String, filename: String, contentType: String) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = contentType == "application/json"
            ? [.json]
            : [.plainText]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? content.write(to: url, atomically: true, encoding: .utf8)
            }
        }
        #else
        // On iOS, write to temp and share
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? content.write(to: tempURL, atomically: true, encoding: .utf8)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first,
              let rootVC = window.rootViewController else { return }
        let ac = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        if let popover = ac.popoverPresentationController {
            popover.sourceView = window
            popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
        }
        rootVC.present(ac, animated: true)
        #endif
    }
}
