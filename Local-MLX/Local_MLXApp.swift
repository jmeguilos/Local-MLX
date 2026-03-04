import SwiftUI
import SwiftData

@main
struct Local_MLXApp: App {
    let dataContainer: SwiftData.ModelContainer
    @State private var modelManager = ModelManager()

    init() {
        do {
            let schema = Schema([
                Conversation.self,
                ChatMessage.self,
                ServerConfig.self,
                Folder.self,
                Persona.self,
            ])
            let config = SwiftData.ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            dataContainer = try SwiftData.ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }

    #if os(iOS)
    @State private var showSplash = true
    #endif

    var body: some Scene {
        WindowGroup {
            ZStack {
                MainView(modelManager: modelManager)
                #if os(iOS)
                if showSplash {
                    SplashScreenView {
                        withAnimation { showSplash = false }
                    }
                }
                #endif
            }
        }
        .modelContainer(dataContainer)
    }
}
