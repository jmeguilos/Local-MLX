import SwiftUI
import SwiftData

@main
struct Local_MLXApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([
                Conversation.self,
                ChatMessage.self,
                ServerConfig.self,
            ])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .modelContainer(modelContainer)
    }
}
