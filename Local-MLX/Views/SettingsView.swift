import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var configs: [ServerConfig]

    @State private var baseURL = ""
    @State private var defaultModel = ""
    @State private var defaultSystemPrompt = ""
    @State private var isConnected: Bool?
    @State private var isCheckingConnection = false
    @State private var connectionError: String?

    private var config: ServerConfig {
        configs.first ?? ServerConfig()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Server URL", text: $baseURL)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()

                    HStack {
                        Button("Check Connection") {
                            checkConnection()
                        }
                        .disabled(isCheckingConnection)

                        Spacer()

                        if isCheckingConnection {
                            ProgressView()
                                .controlSize(.small)
                        } else if let connected = isConnected {
                            Image(systemName: connected ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(connected ? .green : .red)
                            VStack(alignment: .leading) {
                                Text(connected ? "Connected" : "Not reachable")
                                    .font(.caption)
                                    .foregroundStyle(connected ? .green : .red)
                                if let error = connectionError {
                                    Text(error)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Model") {
                    ModelPickerView(
                        selectedModel: $defaultModel,
                        baseURL: baseURL
                    )
                }

                Section("System Prompt") {
                    TextEditor(text: $defaultSystemPrompt)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                baseURL = config.baseURL
                defaultModel = config.defaultModel
                defaultSystemPrompt = config.defaultSystemPrompt
            }
        }
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 400)
        #endif
    }

    private func save() {
        if let existing = configs.first {
            existing.baseURL = baseURL
            existing.defaultModel = defaultModel
            existing.defaultSystemPrompt = defaultSystemPrompt
        } else {
            let newConfig = ServerConfig(
                baseURL: baseURL,
                defaultModel: defaultModel,
                defaultSystemPrompt: defaultSystemPrompt
            )
            modelContext.insert(newConfig)
        }
        try? modelContext.save()
    }

    private func checkConnection() {
        isCheckingConnection = true
        isConnected = nil
        connectionError = nil
        Task {
            let client = MLXServerClient(baseURL: baseURL)
            let (connected, error) = await client.checkConnection()
            isConnected = connected
            connectionError = error
            isCheckingConnection = false
        }
    }
}
