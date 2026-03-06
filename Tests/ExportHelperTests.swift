import Testing
import Foundation
import SwiftData

@Suite("Export Helper")
struct ExportHelperTests {

    // MARK: - Test Helpers

    /// Creates an in-memory model container for testing.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Conversation.self, ChatMessage.self, Folder.self, Persona.self, ServerConfig.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Creates a sample conversation with messages for testing.
    private func makeSampleConversation(container: ModelContainer) -> Conversation {
        let context = container.mainContext
        let conversation = Conversation(title: "Test Chat", systemPrompt: "You are helpful.")
        context.insert(conversation)

        let userMsg = ChatMessage(role: .user, content: "Hello, world!", conversation: conversation)
        conversation.messages.append(userMsg)

        let assistantMsg = ChatMessage(role: .assistant, content: "Hello! How can I help you today?", conversation: conversation)
        assistantMsg.timestamp = userMsg.timestamp.addingTimeInterval(1)
        conversation.messages.append(assistantMsg)

        try? context.save()
        return conversation
    }

    // MARK: - Markdown Tests

    @Test("Markdown export includes title as heading")
    func markdownIncludesTitle() throws {
        let container = try makeContainer()
        let conversation = makeSampleConversation(container: container)
        let markdown = ExportHelper.generateMarkdown(conversation: conversation)

        #expect(markdown.contains("# Test Chat"))
    }

    @Test("Markdown export includes system prompt")
    func markdownIncludesSystemPrompt() throws {
        let container = try makeContainer()
        let conversation = makeSampleConversation(container: container)
        let markdown = ExportHelper.generateMarkdown(conversation: conversation)

        #expect(markdown.contains("**System Prompt:** You are helpful."))
    }

    @Test("Markdown export includes user and assistant messages")
    func markdownIncludesMessages() throws {
        let container = try makeContainer()
        let conversation = makeSampleConversation(container: container)
        let markdown = ExportHelper.generateMarkdown(conversation: conversation)

        #expect(markdown.contains("### User"))
        #expect(markdown.contains("Hello, world!"))
        #expect(markdown.contains("### Assistant"))
        #expect(markdown.contains("Hello! How can I help you today?"))
    }

    @Test("Markdown export includes export date")
    func markdownIncludesDate() throws {
        let container = try makeContainer()
        let conversation = makeSampleConversation(container: container)
        let markdown = ExportHelper.generateMarkdown(conversation: conversation)

        #expect(markdown.contains("*Exported from Local MLX on"))
    }

    @Test("Markdown export handles think blocks")
    func markdownHandlesThinkBlocks() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let conversation = Conversation(title: "Think Test")
        context.insert(conversation)

        let userMsg = ChatMessage(role: .user, content: "Explain something", conversation: conversation)
        conversation.messages.append(userMsg)

        let assistantContent = "<think>Let me reason about this...</think>Here is the explanation."
        let assistantMsg = ChatMessage(role: .assistant, content: assistantContent, conversation: conversation)
        assistantMsg.timestamp = userMsg.timestamp.addingTimeInterval(1)
        conversation.messages.append(assistantMsg)

        try? context.save()

        let markdown = ExportHelper.generateMarkdown(conversation: conversation)

        #expect(markdown.contains("<details>"))
        #expect(markdown.contains("<summary>Thinking</summary>"))
        #expect(markdown.contains("Let me reason about this..."))
        #expect(markdown.contains("Here is the explanation."))
    }

    @Test("Markdown export skips system messages in body")
    func markdownSkipsSystemMessages() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let conversation = Conversation(title: "System Skip Test")
        context.insert(conversation)

        let systemMsg = ChatMessage(role: .system, content: "Hidden system message", conversation: conversation)
        conversation.messages.append(systemMsg)

        let userMsg = ChatMessage(role: .user, content: "Hi", conversation: conversation)
        userMsg.timestamp = systemMsg.timestamp.addingTimeInterval(1)
        conversation.messages.append(userMsg)

        try? context.save()

        let markdown = ExportHelper.generateMarkdown(conversation: conversation)

        #expect(!markdown.contains("Hidden system message"))
        #expect(markdown.contains("Hi"))
    }

    // MARK: - JSON Tests

    @Test("JSON export produces valid JSON with conversation metadata")
    func jsonIncludesMetadata() throws {
        let container = try makeContainer()
        let conversation = makeSampleConversation(container: container)
        let json = ExportHelper.generateJSON(conversation: conversation)

        #expect(json.contains("\"title\""))
        #expect(json.contains("\"Test Chat\""))
        #expect(json.contains("\"exportDate\""))
        #expect(json.contains("\"systemPrompt\""))
        #expect(json.contains("\"messageCount\""))
        #expect(json.contains("\"messages\""))
    }

    @Test("JSON export is valid parseable JSON")
    func jsonIsDecodable() throws {
        let container = try makeContainer()
        let conversation = makeSampleConversation(container: container)
        let json = ExportHelper.generateJSON(conversation: conversation)
        let data = try #require(json.data(using: .utf8))

        // Should parse without error
        let object = try JSONSerialization.jsonObject(with: data)
        let dict = try #require(object as? [String: Any])
        let messages = try #require(dict["messages"] as? [[String: Any]])

        #expect(dict["title"] as? String == "Test Chat")
        #expect(dict["messageCount"] as? Int == messages.count)
    }

    @Test("JSON export includes all message roles and content")
    func jsonIncludesMessages() throws {
        let container = try makeContainer()
        let conversation = makeSampleConversation(container: container)
        let json = ExportHelper.generateJSON(conversation: conversation)

        #expect(json.contains("\"user\""))
        #expect(json.contains("\"assistant\""))
        #expect(json.contains("Hello, world!"))
        #expect(json.contains("Hello! How can I help you today?"))
    }

    @Test("JSON export handles nil system prompt")
    func jsonHandlesNilSystemPrompt() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let conversation = Conversation(title: "No Prompt")
        context.insert(conversation)
        try? context.save()

        let json = ExportHelper.generateJSON(conversation: conversation)

        #expect(json.contains("\"systemPrompt\" : null"))
    }

    // MARK: - Plain Text Tests

    @Test("Plain text export includes title and messages")
    func plainTextIncludesContent() throws {
        let container = try makeContainer()
        let conversation = makeSampleConversation(container: container)
        let text = ExportHelper.generatePlainText(conversation: conversation)

        #expect(text.contains("Test Chat"))
        #expect(text.contains("--- User ---"))
        #expect(text.contains("Hello, world!"))
        #expect(text.contains("--- Assistant ---"))
        #expect(text.contains("Hello! How can I help you today?"))
    }

    @Test("Plain text export includes system prompt")
    func plainTextIncludesSystemPrompt() throws {
        let container = try makeContainer()
        let conversation = makeSampleConversation(container: container)
        let text = ExportHelper.generatePlainText(conversation: conversation)

        #expect(text.contains("System Prompt: You are helpful."))
    }

    // MARK: - Filename Sanitization Tests

    @Test("Sanitize filename removes special characters")
    func sanitizeFilenameSpecialChars() {
        let result = ExportHelper.sanitizeFilename("Hello <World> /test\\file!")
        #expect(!result.contains("<"))
        #expect(!result.contains(">"))
        #expect(!result.contains("/"))
        #expect(!result.contains("\\"))
        #expect(!result.contains("!"))
    }

    @Test("Sanitize filename truncates long names")
    func sanitizeFilenameTruncation() {
        let longName = String(repeating: "a", count: 100)
        let result = ExportHelper.sanitizeFilename(longName)
        #expect(result.count <= 50)
    }

    @Test("Sanitize filename returns default for empty input")
    func sanitizeFilenameEmpty() {
        let result = ExportHelper.sanitizeFilename("")
        #expect(result == "conversation")

        let allSpecial = ExportHelper.sanitizeFilename("!@#$%^&*()")
        #expect(allSpecial == "conversation")
    }

    @Test("Sanitize filename preserves valid characters")
    func sanitizeFilenameValid() {
        let result = ExportHelper.sanitizeFilename("My Chat 2024-01-15")
        #expect(result == "My Chat 2024-01-15")
    }

    // MARK: - Temporary File URL Tests

    @Test("Temporary file URL generates valid file for each format")
    func temporaryFileURLFormats() throws {
        let container = try makeContainer()
        let conversation = makeSampleConversation(container: container)

        for format in ExportHelper.ExportFormat.allCases {
            let url = try #require(ExportHelper.temporaryFileURL(for: conversation, format: format))
            #expect(FileManager.default.fileExists(atPath: url.path))

            let content = try String(contentsOf: url, encoding: .utf8)
            #expect(!content.isEmpty)

            // Cleanup
            try? FileManager.default.removeItem(at: url)
        }
    }

    @Test("Temporary file URL has correct extensions")
    func temporaryFileURLExtensions() throws {
        let container = try makeContainer()
        let conversation = makeSampleConversation(container: container)

        let mdURL = try #require(ExportHelper.temporaryFileURL(for: conversation, format: .markdown))
        #expect(mdURL.pathExtension == "md")

        let jsonURL = try #require(ExportHelper.temporaryFileURL(for: conversation, format: .json))
        #expect(jsonURL.pathExtension == "json")

        let txtURL = try #require(ExportHelper.temporaryFileURL(for: conversation, format: .plainText))
        #expect(txtURL.pathExtension == "txt")

        // Cleanup
        try? FileManager.default.removeItem(at: mdURL)
        try? FileManager.default.removeItem(at: jsonURL)
        try? FileManager.default.removeItem(at: txtURL)
    }

    // MARK: - Date Formatting Tests

    @Test("Formatted date is not empty")
    func formattedDateNotEmpty() {
        let result = ExportHelper.formattedDate(Date())
        #expect(!result.isEmpty)
    }
}
