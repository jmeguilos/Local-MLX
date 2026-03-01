import Foundation
import Hub
import MLX
import MLXLLM
import MLXLMCommon

enum ModelState: Equatable {
    case notDownloaded
    case downloading(Double)
    case ready
    case loading
    case loaded
    case error(String)

    static func == (lhs: ModelState, rhs: ModelState) -> Bool {
        switch (lhs, rhs) {
        case (.notDownloaded, .notDownloaded),
            (.ready, .ready),
            (.loading, .loading),
            (.loaded, .loaded):
            return true
        case (.downloading(let a), .downloading(let b)):
            return a == b
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

@Observable
final class ModelManager {
    static let defaultModelID = "mlx-community/Qwen3-4B-4bit"

    var modelState: ModelState = .notDownloaded
    var modelContainer: ModelContainer?

    private var downloadTask: Task<Void, Never>?

    func downloadAndLoad(modelID: String) {
        switch modelState {
        case .notDownloaded, .error:
            startDownloadAndLoad(modelID: modelID)
        default:
            return
        }
    }

    private func startDownloadAndLoad(modelID: String) {
        modelState = .downloading(0)

        downloadTask = Task {
            do {
                let configuration = ModelConfiguration(id: modelID)
                let hub = HubApi(
                    downloadBase: FileManager.default.urls(
                        for: .cachesDirectory, in: .userDomainMask
                    ).first
                )

                // Download model files
                _ = try await downloadModel(
                    hub: hub,
                    configuration: configuration
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.modelState = .downloading(progress.fractionCompleted)
                    }
                }

                if Task.isCancelled { return }

                // Load into memory
                modelState = .loading
                let container = try await LLMModelFactory.shared.loadContainer(
                    hub: hub,
                    configuration: configuration
                )

                if Task.isCancelled { return }

                modelContainer = container
                modelState = .loaded
            } catch {
                if !Task.isCancelled {
                    modelState = .error(error.localizedDescription)
                }
            }
        }
    }

    func loadModel(modelID: String) {
        guard modelState == .ready || modelState == .notDownloaded else { return }

        modelState = .loading

        downloadTask = Task {
            do {
                let configuration = ModelConfiguration(id: modelID)
                let hub = HubApi(
                    downloadBase: FileManager.default.urls(
                        for: .cachesDirectory, in: .userDomainMask
                    ).first
                )

                let container = try await LLMModelFactory.shared.loadContainer(
                    hub: hub,
                    configuration: configuration
                )

                if Task.isCancelled { return }

                modelContainer = container
                modelState = .loaded
            } catch {
                if !Task.isCancelled {
                    modelState = .error(error.localizedDescription)
                }
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        modelContainer = nil
        modelState = .notDownloaded
    }

    func unloadModel() {
        downloadTask?.cancel()
        downloadTask = nil
        modelContainer = nil
        modelState = .ready
    }

    func checkCachedModel(modelID: String) {
        let hub = HubApi(
            downloadBase: FileManager.default.urls(
                for: .cachesDirectory, in: .userDomainMask
            ).first
        )
        let repo = Hub.Repo(id: modelID)
        let cacheDir = hub.localRepoLocation(repo)

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: cacheDir.path),
            let contents = try? fileManager.contentsOfDirectory(atPath: cacheDir.path),
            contents.contains(where: { $0.hasSuffix(".safetensors") })
        {
            modelState = .ready
        } else {
            modelState = .notDownloaded
        }
    }

    func retryDownload(modelID: String) {
        modelState = .notDownloaded
        startDownloadAndLoad(modelID: modelID)
    }
}
