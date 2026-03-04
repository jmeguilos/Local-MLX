import Foundation
import SwiftData

@Model
final class Persona {
    var id: UUID
    var name: String
    var systemPrompt: String
    var modelID: String?
    var temperature: Double?
    var maxTokens: Int?
    var icon: String

    init(
        name: String,
        systemPrompt: String = "",
        modelID: String? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        icon: String = "person.circle"
    ) {
        self.id = UUID()
        self.name = name
        self.systemPrompt = systemPrompt
        self.modelID = modelID
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.icon = icon
    }
}
