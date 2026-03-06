import Foundation
import SwiftData
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension Notification.Name {
    static let exportError = Notification.Name("exportError")
}

enum ExportHelper {

    // MARK: - Export Format

    enum ExportFormat: String, CaseIterable {
        case markdown
        case json
        case plainText

        var fileExtension: String {
            switch self {
            case .markdown: return "md"
            case .json: return "json"
            case .plainText: return "txt"
            }
        }

        var utType: UTType {
            switch self {
            case .markdown: return UTType(filenameExtension: "md") ?? .plainText
            case .json: return .json
            case .plainText: return .plainText
            }
        }
    }

    // MARK: - Public Export Methods (return error string or nil)

    @discardableResult
    static func exportMarkdown(conversation: Conversation) -> String? {
        return export(conversation: conversation, format: .markdown)
    }

    @discardableResult
    static func exportJSON(conversation: Conversation) -> String? {
        return export(conversation: conversation, format: .json)
    }

    @discardableResult
    static func exportPlainText(conversation: Conversation) -> String? {
        return export(conversation: conversation, format: .plainText)
    }

    // MARK: - Content Generation

    static func generateMarkdown(conversation: Conversation) -> String {
        var lines: [String] = []

        lines.append("# \(conversation.title)")
        lines.append("")

        if let systemPrompt = conversation.systemPrompt, !systemPrompt.isEmpty {
            lines.append("**System Prompt:** \(systemPrompt)")
            lines.append("")
        }

        lines.append("---")
        lines.append("")

        let sortedMessages = conversation.messages.sorted { $0.timestamp < $1.timestamp }

        for message in sortedMessages {
            guard message.role != .system else { continue }

            let roleName = message.role == .user ? "User" : "Assistant"
            lines.append("### \(roleName)")
            lines.append("")

            let content = processThinkBlocks(message.content)
            lines.append(content)
            lines.append("")
        }

        lines.append("---")
        lines.append("")
        lines.append("*Exported from Local MLX on \(formattedDate(Date()))*")

        return lines.joined(separator: "\n")
    }

    static func generateJSON(conversation: Conversation) -> String {
        let sortedMessages = conversation.messages.sorted { $0.timestamp < $1.timestamp }

        var messagesArray: [[String: Any]] = []
        for message in sortedMessages {
            var dict: [String: Any] = [
                "role": message.role.rawValue,
                "content": message.content,
                "timestamp": ISO8601DateFormatter().string(from: message.timestamp)
            ]
            if message.isEdited {
                dict["edited"] = true
            }
            messagesArray.append(dict)
        }

        var root: [String: Any] = [
            "title": conversation.title,
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "messageCount": messagesArray.count,
            "messages": messagesArray
        ]

        if let systemPrompt = conversation.systemPrompt {
            root["systemPrompt"] = systemPrompt
        } else {
            root["systemPrompt"] = NSNull()
        }

        if let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    }

    static func generatePlainText(conversation: Conversation) -> String {
        var lines: [String] = []

        lines.append(conversation.title)
        lines.append(String(repeating: "=", count: conversation.title.count))
        lines.append("")

        if let systemPrompt = conversation.systemPrompt, !systemPrompt.isEmpty {
            lines.append("System Prompt: \(systemPrompt)")
            lines.append("")
        }

        let sortedMessages = conversation.messages.sorted { $0.timestamp < $1.timestamp }

        for message in sortedMessages {
            guard message.role != .system else { continue }

            let roleName = message.role == .user ? "User" : "Assistant"
            lines.append("--- \(roleName) ---")
            lines.append(message.content)
            lines.append("")
        }

        lines.append("Exported from Local MLX on \(formattedDate(Date()))")

        return lines.joined(separator: "\n")
    }

    // MARK: - Filename & Date Helpers

    static func sanitizeFilename(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "<>:\"/\\|?!*")
        var sanitized = name.components(separatedBy: invalidChars).joined()
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)

        if sanitized.isEmpty {
            return "conversation"
        }

        if sanitized.count > 50 {
            sanitized = String(sanitized.prefix(50))
        }

        return sanitized
    }

    static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Temporary File URL

    static func temporaryFileURL(for conversation: Conversation, format: ExportFormat) -> URL? {
        let content: String
        switch format {
        case .markdown: content = generateMarkdown(conversation: conversation)
        case .json: content = generateJSON(conversation: conversation)
        case .plainText: content = generatePlainText(conversation: conversation)
        }

        let filename = sanitizeFilename(conversation.title)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
            .appendingPathExtension(format.fileExtension)

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Private Helpers

    private static func export(conversation: Conversation, format: ExportFormat) -> String? {
        guard let url = temporaryFileURL(for: conversation, format: format) else {
            return "Failed to create export file."
        }

        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.utType]
        panel.nameFieldStringValue = url.lastPathComponent
        panel.isExtensionHidden = false

        let response = panel.runModal()
        defer { try? FileManager.default.removeItem(at: url) }

        guard response == .OK, let destination = panel.url else {
            return nil // user cancelled — not an error
        }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            return nil
        } catch {
            return error.localizedDescription
        }
        #else
        // On iOS, present share sheet
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first,
              let rootVC = window.rootViewController else {
            try? FileManager.default.removeItem(at: url)
            return "Unable to present share sheet."
        }

        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activityVC.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: url)
        }

        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = window
            popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
        }

        rootVC.present(activityVC, animated: true)
        return nil
        #endif
    }

    private static func processThinkBlocks(_ content: String) -> String {
        let pattern = #"<think>(.*?)</think>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else {
            return content
        }

        var result = content
        let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))

        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: content),
                  let thinkRange = Range(match.range(at: 1), in: content) else { continue }

            let thinkContent = String(content[thinkRange])
            let replacement = """
            <details>
            <summary>Thinking</summary>

            \(thinkContent)

            </details>
            """
            result = result.replacingCharacters(in: fullRange, with: replacement)
        }

        return result
    }
}
