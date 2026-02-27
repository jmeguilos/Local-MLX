import SwiftUI

struct ModelPickerView: View {
    @Binding var selectedModel: String
    let baseURL: String

    @State private var availableModels: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Model")
                Spacer()
                Button("Refresh") {
                    fetchModels()
                }
                .font(.caption)
                .disabled(isLoading)
            }

            if isLoading {
                ProgressView("Loading models...")
            } else if availableModels.isEmpty {
                TextField("Model name", text: $selectedModel)
                    .autocorrectionDisabled()
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Picker("Select model", selection: $selectedModel) {
                    if selectedModel.isEmpty {
                        Text("Select a model").tag("")
                    }
                    ForEach(availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .labelsHidden()
            }
        }
        .onAppear {
            fetchModels()
        }
    }

    private func fetchModels() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let client = MLXServerClient(baseURL: baseURL)
                let models = try await client.fetchModels()
                availableModels = models
                if selectedModel.isEmpty, let first = models.first {
                    selectedModel = first
                }
            } catch {
                errorMessage = "Could not fetch models. Enter manually."
            }
            isLoading = false
        }
    }
}
