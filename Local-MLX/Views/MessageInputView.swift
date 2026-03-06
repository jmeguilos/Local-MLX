import SwiftUI
import PhotosUI

struct MessageInputView: View {
    let isGenerating: Bool
    let currentModel: String
    let availableModels: [String]
    var modelManager: ModelManager? = nil
    var serverConfig: ServerConfig? = nil
    let onSend: (String) -> Void
    let onStop: () -> Void
    let onModelChange: (String) -> Void
    var onLocalModelChange: ((String) -> Void)? = nil
    var onToggleParameters: (() -> Void)? = nil
    var onImageAttach: (([Data]) -> Void)? = nil

    @State private var inputText = ""
    @FocusState private var isFocused: Bool
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var attachedImages: [Data] = []

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachedImages.isEmpty
    }

    var body: some View {
        VStack(spacing: 8) {
            // Model chip: interactive for switching
            if let manager = modelManager, let config = serverConfig {
                HStack {
                    if config.isLocalMode {
                        LocalModelSwitchChip(
                            modelManager: manager,
                            config: config,
                            onLocalModelChange: onLocalModelChange
                        )
                    } else if !availableModels.isEmpty {
                        modelPickerChip
                    } else {
                        ModelStatusChip(modelManager: manager, config: config)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
            } else if !availableModels.isEmpty {
                HStack {
                    modelPickerChip
                    Spacer()
                }
                .padding(.horizontal, 20)
            }

            // Image thumbnails
            if !attachedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(attachedImages.enumerated()), id: \.offset) { idx, imageData in
                            ZStack(alignment: .topTrailing) {
                                #if os(macOS)
                                if let nsImage = NSImage(data: imageData) {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                #else
                                if let uiImage = UIImage(data: imageData) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                #endif
                                Button {
                                    attachedImages.remove(at: idx)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                        .background(Circle().fill(.black.opacity(0.5)))
                                }
                                .buttonStyle(.plain)
                                .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                // Parameters toggle
                if onToggleParameters != nil {
                    Button {
                        onToggleParameters?()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 10)
                    .padding(.bottom, 10)
                }

                // Image attachment (F18)
                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: 4,
                    matching: .images
                ) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, onToggleParameters == nil ? 10 : 0)
                .padding(.bottom, 10)
                .onChange(of: selectedPhotos) {
                    Task {
                        var newImages: [Data] = []
                        for item in selectedPhotos {
                            if let data = try? await item.loadTransferable(type: Data.self) {
                                newImages.append(data)
                            }
                        }
                        attachedImages.append(contentsOf: newImages)
                        selectedPhotos = []
                    }
                }

                // Text input
                TextField("Message", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .focused($isFocused)
                    .onSubmit {
                        #if os(macOS)
                        send()
                        #endif
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                // Action button
                actionButton
                    .padding(.trailing, 6)
                    .padding(.bottom, 6)
            }
            .glassEffect(.regular.interactive(), in: .capsule)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Model Picker Chip

    private var modelPickerChip: some View {
        Menu {
            ForEach(availableModels, id: \.self) { model in
                Button {
                    onModelChange(model)
                } label: {
                    HStack {
                        Text(model)
                        if model == currentModel {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.caption2)
                Text(currentModel.isEmpty ? "Select Model" : truncatedModel)
                    .font(.caption)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var truncatedModel: String {
        if currentModel.count > 28 {
            return String(currentModel.prefix(28)) + "..."
        }
        return currentModel
    }

    // MARK: - Action Button

    @ViewBuilder
    private var actionButton: some View {
        if isGenerating {
            Button(action: onStop) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.primary)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .transition(.scale.combined(with: .opacity))
        } else {
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .transition(.scale.combined(with: .opacity))
        }
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachedImages.isEmpty else { return }

        if !attachedImages.isEmpty {
            onImageAttach?(attachedImages)
            attachedImages = []
        }

        inputText = ""
        onSend(text.isEmpty ? "[Image attached]" : text)
    }
}

// MARK: - Local Model Switch Chip

struct LocalModelSwitchChip: View {
    let modelManager: ModelManager
    let config: ServerConfig
    var onLocalModelChange: ((String) -> Void)?

    private var shortModelName: String {
        let id = config.localModelID
        if let lastSlash = id.lastIndex(of: "/") {
            return String(id[id.index(after: lastSlash)...])
        }
        return id
    }

    private var statusLabel: String {
        switch modelManager.modelState {
        case .loaded:
            return shortModelName
        case .loading:
            return "Loading model..."
        case .downloading(let progress):
            return "Downloading \(Int(progress * 100))%..."
        default:
            return "No model loaded"
        }
    }

    var body: some View {
        if config.savedLocalModelIDs.isEmpty {
            ModelStatusChip(modelManager: modelManager, config: config)
        } else {
            Menu {
                ForEach(config.savedLocalModelIDs, id: \.self) { modelID in
                    Button {
                        guard modelID != config.localModelID else { return }
                        modelManager.unloadModel()
                        onLocalModelChange?(modelID)
                        modelManager.loadModel(modelID: modelID)
                    } label: {
                        HStack {
                            Text(modelID)
                            if modelID == config.localModelID {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    switch modelManager.modelState {
                    case .loaded:
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                    case .loading:
                        ProgressView()
                            .controlSize(.mini)
                    case .downloading:
                        ProgressView()
                            .controlSize(.mini)
                    default:
                        Circle()
                            .fill(.orange)
                            .frame(width: 6, height: 6)
                    }

                    Text(statusLabel)
                        .font(.caption)
                        .lineLimit(1)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}
