import Foundation
import SwiftData

@Model
final class ServerConfig {
    var id: UUID
    var baseURL: String
    var defaultModel: String
    var defaultSystemPrompt: String
    var inferenceMode: String = "server"
    var localModelID: String = "mlx-community/Qwen3-4B-4bit"
    var savedLocalModelIDs: [String] = []
    var savedServerModels: [String] = []

    var isLocalMode: Bool {
        inferenceMode == "local"
    }

    init(
        baseURL: String = "http://localhost:8080",
        defaultModel: String = "",
        defaultSystemPrompt: String = "You are a helpful assistant.",
        inferenceMode: String = "server",
        localModelID: String = "mlx-community/Qwen3-4B-4bit"
    ) {
        self.id = UUID()
        self.baseURL = baseURL
        self.defaultModel = defaultModel
        self.defaultSystemPrompt = defaultSystemPrompt
        self.inferenceMode = inferenceMode
        self.localModelID = localModelID
    }
}
