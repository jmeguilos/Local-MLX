import SwiftUI
import SwiftData

struct SettingsView: View {
    var modelManager: ModelManager

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var configs: [ServerConfig]

    @State private var baseURL = ""
    @State private var defaultModel = ""
    @State private var defaultSystemPrompt = ""
    @State private var inferenceMode = "server"
    @State private var localModelID = ModelManager.defaultModelID
    @State private var isConnected: Bool?
    @State private var isCheckingConnection = false
    @State private var connectionError: String?
    @State private var savedLocalModelIDs: [String] = []
    @State private var savedServerModels: [String] = []
    @State private var newSavedModelID = ""

    private var config: ServerConfig {
        configs.first ?? ServerConfig()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Inference Mode") {
                    Picker("Mode", selection: $inferenceMode) {
                        Text("Server").tag("server")
                        Text("On-Device").tag("local")
                    }
                    .pickerStyle(.segmented)
                }

                if inferenceMode == "server" {
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
                } else {
                    Section("Local Model") {
                        TextField("Model ID", text: $localModelID)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif

                        ModelDownloadView(
                            modelManager: modelManager,
                            modelID: localModelID
                        )
                    }
                }

                if inferenceMode == "server" {
                    Section("Saved Server Models") {
                        ForEach(savedServerModels, id: \.self) { model in
                            Text(model)
                        }
                        .onDelete { indexSet in
                            savedServerModels.remove(atOffsets: indexSet)
                        }
                        HStack {
                            TextField("Add model name...", text: $newSavedModelID)
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                            Button {
                                let trimmed = newSavedModelID.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty, !savedServerModels.contains(trimmed) else { return }
                                savedServerModels.append(trimmed)
                                newSavedModelID = ""
                            } label: {
                                Image(systemName: "plus.circle.fill")
                            }
                            .disabled(newSavedModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                } else {
                    Section("Saved Local Models") {
                        ForEach(savedLocalModelIDs, id: \.self) { model in
                            Text(model)
                        }
                        .onDelete { indexSet in
                            savedLocalModelIDs.remove(atOffsets: indexSet)
                        }
                        HStack {
                            TextField("Add model ID...", text: $newSavedModelID)
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                            Button {
                                let trimmed = newSavedModelID.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty, !savedLocalModelIDs.contains(trimmed) else { return }
                                savedLocalModelIDs.append(trimmed)
                                newSavedModelID = ""
                            } label: {
                                Image(systemName: "plus.circle.fill")
                            }
                            .disabled(newSavedModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
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
                inferenceMode = config.inferenceMode
                localModelID = config.localModelID
                savedLocalModelIDs = config.savedLocalModelIDs
                savedServerModels = config.savedServerModels
            }
        }
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 400)
        #endif
    }

    private func save() {
        // Auto-append current model to saved list if not already present
        if inferenceMode == "local" {
            let trimmedLocal = localModelID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedLocal.isEmpty && !savedLocalModelIDs.contains(trimmedLocal) {
                savedLocalModelIDs.append(trimmedLocal)
            }
        } else {
            let trimmedServer = defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedServer.isEmpty && !savedServerModels.contains(trimmedServer) {
                savedServerModels.append(trimmedServer)
            }
        }

        if let existing = configs.first {
            existing.baseURL = baseURL
            existing.defaultModel = defaultModel
            existing.defaultSystemPrompt = defaultSystemPrompt
            existing.inferenceMode = inferenceMode
            existing.localModelID = localModelID
            existing.savedLocalModelIDs = savedLocalModelIDs
            existing.savedServerModels = savedServerModels
        } else {
            let newConfig = ServerConfig(
                baseURL: baseURL,
                defaultModel: defaultModel,
                defaultSystemPrompt: defaultSystemPrompt,
                inferenceMode: inferenceMode,
                localModelID: localModelID
            )
            newConfig.savedLocalModelIDs = savedLocalModelIDs
            newConfig.savedServerModels = savedServerModels
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
