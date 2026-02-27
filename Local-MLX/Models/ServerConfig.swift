import Foundation
import SwiftData

@Model
final class ServerConfig {
    var id: UUID
    var baseURL: String
    var defaultModel: String
    var defaultSystemPrompt: String

    init(
        baseURL: String = "http://localhost:8080",
        defaultModel: String = "",
        defaultSystemPrompt: String = "You are a helpful assistant."
    ) {
        self.id = UUID()
        self.baseURL = baseURL
        self.defaultModel = defaultModel
        self.defaultSystemPrompt = defaultSystemPrompt
    }
}
