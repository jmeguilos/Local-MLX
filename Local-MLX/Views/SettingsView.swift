import SwiftUI
import SwiftData

struct SettingsView: View {
    var modelManager: ModelManager

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var configs: [ServerConfig]
    @Query(sort: \Persona.name) private var personas: [Persona]

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
    @State private var showNewPersona = false
    @State private var editingPersona: Persona?

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

                // Personas Section (F17)
                Section("Personas") {
                    ForEach(personas) { persona in
                        HStack {
                            Image(systemName: persona.icon)
                                .font(.title3)
                                .foregroundStyle(.purple)
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(persona.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                if !persona.systemPrompt.isEmpty {
                                    Text(persona.systemPrompt.prefix(60) + (persona.systemPrompt.count > 60 ? "..." : ""))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Button {
                                editingPersona = persona
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            modelContext.delete(personas[index])
                        }
                        try? modelContext.save()
                    }

                    Button {
                        showNewPersona = true
                    } label: {
                        Label("New Persona", systemImage: "plus")
                    }
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
            .sheet(isPresented: $showNewPersona) {
                PersonaEditorView(persona: nil)
            }
            .sheet(item: $editingPersona) { persona in
                PersonaEditorView(persona: persona)
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

// MARK: - Persona Editor

struct PersonaEditorView: View {
    let persona: Persona?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var systemPrompt = ""
    @State private var icon = "person.circle"
    @State private var temperature: Double?
    @State private var maxTokens: Int?
    @State private var useCustomTemp = false
    @State private var useCustomTokens = false
    @State private var tempValue: Double = 0.7
    @State private var tokensValue: Int = 2048

    private let iconOptions = [
        "person.circle", "brain", "book", "wrench.and.screwdriver",
        "paintbrush", "code.forking", "globe", "lightbulb"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Persona name", text: $name)
                }

                Section("Icon") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
                        ForEach(iconOptions, id: \.self) { opt in
                            Button {
                                icon = opt
                            } label: {
                                Image(systemName: opt)
                                    .font(.title2)
                                    .frame(width: 40, height: 40)
                                    .background(icon == opt ? Color.accentColor.opacity(0.2) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("System Prompt") {
                    TextEditor(text: $systemPrompt)
                        .frame(minHeight: 80)
                }

                Section("Parameters (Optional)") {
                    Toggle("Custom Temperature", isOn: $useCustomTemp)
                    if useCustomTemp {
                        HStack {
                            Text("Temperature: \(tempValue, specifier: "%.2f")")
                                .font(.caption)
                            Slider(value: $tempValue, in: 0...2, step: 0.05)
                        }
                    }
                    Toggle("Custom Max Tokens", isOn: $useCustomTokens)
                    if useCustomTokens {
                        Stepper("Max Tokens: \(tokensValue)", value: $tokensValue, in: 256...8192, step: 256)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(persona == nil ? "New Persona" : "Edit Persona")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        savePersona()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let p = persona {
                    name = p.name
                    systemPrompt = p.systemPrompt
                    icon = p.icon
                    if let t = p.temperature {
                        useCustomTemp = true
                        tempValue = t
                    }
                    if let m = p.maxTokens {
                        useCustomTokens = true
                        tokensValue = m
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 350)
        #endif
    }

    private func savePersona() {
        if let existing = persona {
            existing.name = name
            existing.systemPrompt = systemPrompt
            existing.icon = icon
            existing.temperature = useCustomTemp ? tempValue : nil
            existing.maxTokens = useCustomTokens ? tokensValue : nil
        } else {
            let p = Persona(
                name: name,
                systemPrompt: systemPrompt,
                temperature: useCustomTemp ? tempValue : nil,
                maxTokens: useCustomTokens ? tokensValue : nil,
                icon: icon
            )
            modelContext.insert(p)
        }
        try? modelContext.save()
    }
}
