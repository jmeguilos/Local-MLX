import SwiftUI

struct ModelDownloadView: View {
    var modelManager: ModelManager
    let modelID: String

    var body: some View {
        switch modelManager.modelState {
        case .notDownloaded:
            VStack(alignment: .leading, spacing: 8) {
                Text(modelID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("~2.3 GB download")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Button("Download Model") {
                    modelManager.downloadAndLoad(modelID: modelID)
                }
            }

        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: progress) {
                    Text("Downloading... \(Int(progress * 100))%")
                        .font(.caption)
                }
                Button("Cancel", role: .destructive) {
                    modelManager.cancelDownload()
                }
                .font(.caption)
            }

        case .ready:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Downloaded")
                    .font(.caption)
                Spacer()
                Button("Load into Memory") {
                    modelManager.loadModel(modelID: modelID)
                }
                .font(.caption)
            }

        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading model...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .loaded:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Ready")
                    .font(.caption)
                    .foregroundStyle(.green)
                Spacer()
                Button("Unload from Memory") {
                    modelManager.unloadModel()
                }
                .font(.caption)
            }

        case .error(let message):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
                Button("Retry") {
                    modelManager.retryDownload(modelID: modelID)
                }
                .font(.caption)
            }
        }
    }
}
