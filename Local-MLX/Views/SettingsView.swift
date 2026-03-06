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
                // MARK: - Inference Mode
                Section {
                    Picker(selection: $inferenceMode) {
                        Label("Server", systemImage: "server.rack")
                            .tag("server")
                        Label("On-Device", systemImage: "iphone")
                            .tag("local")
                    } label: {
                        Label("Inference Mode", systemImage: "cpu")
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(inferenceMode == "server"
                         ? "Connect to an MLX server for inference."
                         : "Run models locally on this device using MLX.")
                }

                // MARK: - Server / Local Config
                if inferenceMode == "server" {
                    serverSection
                    serverModelSection
                    savedServerModelsSection
                } else {
                    localModelSection
                    savedLocalModelsSection
                }

                // MARK: - System Prompt
                systemPromptSection

                // MARK: - Personas
                personasSection
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
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
        .frame(minWidth: 520, idealWidth: 580, minHeight: 500, idealHeight: 600)
        #endif
    }

    // MARK: - Server Section

    private var serverSection: some View {
        Section {
            LabeledContent {
                TextField("http://localhost:8080", text: $baseURL)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            } label: {
                Label("URL", systemImage: "link")
            }

            connectionStatusRow
        } header: {
            Label("Server Connection", systemImage: "antenna.radiowaves.left.and.right")
        }
    }

    private var connectionStatusRow: some View {
        HStack {
            Button {
                checkConnection()
            } label: {
                HStack(spacing: 6) {
                    if isCheckingConnection {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "bolt.horizontal.circle")
                    }
                    Text(isCheckingConnection ? "Checking…" : "Test Connection")
                }
            }
            .disabled(isCheckingConnection || baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()

            if let connected = isConnected, !isCheckingConnection {
                HStack(spacing: 5) {
                    Image(systemName: connected ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(connected ? .green : .red)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(connected ? "Connected" : "Unreachable")
                            .font(.caption)
                            .foregroundStyle(connected ? .green : .red)
                        if let error = connectionError {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isConnected)
        .animation(.easeInOut(duration: 0.2), value: isCheckingConnection)
    }

    // MARK: - Server Model Section

    private var serverModelSection: some View {
        Section {
            ModelPickerView(
                selectedModel: $defaultModel,
                baseURL: baseURL
            )
        } header: {
            Label("Default Model", systemImage: "cube")
        }
    }

    // MARK: - Saved Server Models

    private var savedServerModelsSection: some View {
        Section {
            if savedServerModels.isEmpty {
                Text("No saved models yet.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(savedServerModels, id: \.self) { model in
                    HStack(spacing: 10) {
                        Image(systemName: "cube")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(model)
                            .lineLimit(1)
                    }
                }
                .onDelete { indexSet in
                    savedServerModels.remove(atOffsets: indexSet)
                }
            }

            addModelRow(collection: $savedServerModels, placeholder: "Add model name…")
        } header: {
            Label("Saved Server Models", systemImage: "star")
        } footer: {
            Text("Saved models appear in the model switcher for quick access.")
        }
    }

    // MARK: - Local Model Section

    private var localModelSection: some View {
        Section {
            LabeledContent {
                TextField("mlx-community/model-name", text: $localModelID)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .multilineTextAlignment(.trailing)
            } label: {
                Label("Model ID", systemImage: "shippingbox")
            }

            ModelDownloadView(
                modelManager: modelManager,
                modelID: localModelID
            )
        } header: {
            Label("Local Model", systemImage: "desktopcomputer")
        } footer: {
            Text("Enter a Hugging Face model ID. The model will be downloaded and cached locally.")
        }
    }

    // MARK: - Saved Local Models

    private var savedLocalModelsSection: some View {
        Section {
            if savedLocalModelIDs.isEmpty {
                Text("No saved models yet.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(savedLocalModelIDs, id: \.self) { model in
                    HStack(spacing: 10) {
                        Image(systemName: "shippingbox")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(model)
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                }
                .onDelete { indexSet in
                    savedLocalModelIDs.remove(atOffsets: indexSet)
                }
            }

            addModelRow(collection: $savedLocalModelIDs, placeholder: "Add model ID…")
        } header: {
            Label("Saved Local Models", systemImage: "star")
        } footer: {
            Text("Switch between saved models using the chip above the input field.")
        }
    }

    // MARK: - System Prompt

    private var systemPromptSection: some View {
        Section {
            ZStack(alignment: .topLeading) {
                if defaultSystemPrompt.isEmpty {
                    Text("Enter a default system prompt…")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $defaultSystemPrompt)
                    .frame(minHeight: 100)
            }
        } header: {
            Label("Default System Prompt", systemImage: "text.bubble")
        } footer: {
            Text("Applied to new conversations. Individual chats can override this.")
        }
    }

    // MARK: - Personas

    private var personasSection: some View {
        Section {
            if personas.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "theatermasks")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("No personas yet")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                    Text("Create personas with custom system prompts for quick access.")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            } else {
                ForEach(personas) { persona in
                    Button {
                        editingPersona = persona
                    } label: {
                        personaRow(persona)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        modelContext.delete(personas[index])
                    }
                    try? modelContext.save()
                }
            }

            Button {
                showNewPersona = true
            } label: {
                Label("New Persona", systemImage: "plus.circle.fill")
            }
        } header: {
            Label("Personas", systemImage: "theatermasks")
        }
    }

    private func personaRow(_ persona: Persona) -> some View {
        HStack(spacing: 12) {
            Image(systemName: persona.icon)
                .font(.title3)
                .foregroundStyle(.purple)
                .frame(width: 32, height: 32)
                .background(Color.purple.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(persona.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                if !persona.systemPrompt.isEmpty {
                    Text(persona.systemPrompt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if persona.temperature != nil || persona.maxTokens != nil {
                    HStack(spacing: 8) {
                        if let temp = persona.temperature {
                            Label("Temp \(temp, specifier: "%.2f")", systemImage: "thermometer.medium")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if let tokens = persona.maxTokens {
                            Label("\(tokens) tokens", systemImage: "number")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.quaternary)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Shared Add-Model Row

    private func addModelRow(collection: Binding<[String]>, placeholder: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            TextField(placeholder, text: $newSavedModelID)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .onSubmit {
                    addModel(to: collection)
                }

            Button {
                addModel(to: collection)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(
                        newSavedModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.secondary.opacity(0.3)
                            : Color.accentColor
                    )
            }
            .buttonStyle(.plain)
            .disabled(newSavedModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func addModel(to collection: Binding<[String]>) {
        let trimmed = newSavedModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !collection.wrappedValue.contains(trimmed) else { return }
        withAnimation {
            collection.wrappedValue.append(trimmed)
        }
        newSavedModelID = ""
    }

    // MARK: - Save & Connection

    private func save() {
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
    @State private var useCustomTemp = false
    @State private var useCustomTokens = false
    @State private var tempValue: Double = 0.7
    @State private var tokensValue: Int = 2048

    private let iconOptions = [
        "person.circle", "brain", "book", "wrench.and.screwdriver",
        "paintbrush", "code.forking", "globe", "lightbulb",
        "graduationcap", "stethoscope", "pencil.and.outline", "music.note"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Persona name", text: $name)
                } header: {
                    Label("Name", systemImage: "textformat")
                }

                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 48))], spacing: 10) {
                        ForEach(iconOptions, id: \.self) { opt in
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    icon = opt
                                }
                            } label: {
                                Image(systemName: opt)
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        icon == opt
                                            ? Color.purple.opacity(0.2)
                                            : Color.secondary.opacity(0.08)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(
                                                icon == opt ? Color.purple : Color.clear,
                                                lineWidth: 2
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Label("Icon", systemImage: "paintpalette")
                }

                Section {
                    ZStack(alignment: .topLeading) {
                        if systemPrompt.isEmpty {
                            Text("Enter a system prompt for this persona…")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $systemPrompt)
                            .frame(minHeight: 100)
                    }
                } header: {
                    Label("System Prompt", systemImage: "text.bubble")
                }

                Section {
                    Toggle(isOn: $useCustomTemp) {
                        Label("Custom Temperature", systemImage: "thermometer.medium")
                    }
                    if useCustomTemp {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(tempValue, specifier: "%.2f")")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Slider(value: $tempValue, in: 0...2, step: 0.05)
                        }
                        .padding(.leading, 4)
                    }

                    Toggle(isOn: $useCustomTokens) {
                        Label("Custom Max Tokens", systemImage: "number")
                    }
                    if useCustomTokens {
                        Stepper(value: $tokensValue, in: 256...8192, step: 256) {
                            Text("\(tokensValue)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 4)
                    }
                } header: {
                    Label("Parameters", systemImage: "slider.horizontal.3")
                } footer: {
                    Text("Leave off to use the conversation defaults.")
                }
            }
            .navigationTitle(persona == nil ? "New Persona" : "Edit Persona")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        savePersona()
                        dismiss()
                    }
                    .fontWeight(.semibold)
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
        .frame(minWidth: 440, minHeight: 400)
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
