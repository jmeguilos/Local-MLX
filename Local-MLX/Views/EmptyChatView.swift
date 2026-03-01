import SwiftUI

struct EmptyChatView: View {
    let onSuggestionTap: (String) -> Void
    var modelManager: ModelManager? = nil
    var serverConfig: ServerConfig? = nil

    @State private var dynamicSuggestions: [(icon: String, text: String)] = SuggestionGenerator.fallbackSuggestions

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(.purple.gradient)

            Text("How can I help?")
                .font(.title2)
                .fontWeight(.semibold)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ], spacing: 10) {
                ForEach(dynamicSuggestions, id: \.text) { suggestion in
                    Button {
                        onSuggestionTap(suggestion.text)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: suggestion.icon)
                                .font(.subheadline)
                                .foregroundStyle(.purple)
                                .frame(width: 20)

                            Text(suggestion.text)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.userMessageBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, 24)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            guard let config = serverConfig, let manager = modelManager else { return }
            let results = await SuggestionGenerator.generateSuggestions(config: config, modelManager: manager)
            dynamicSuggestions = results
        }
    }
}
