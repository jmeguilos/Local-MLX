import Foundation

enum WebSearchService {

    struct SearchResult: Sendable {
        let title: String
        let url: String
        let snippet: String
    }

    struct DuckDuckGoResponse: Decodable {
        var Abstract: String?
        var AbstractText: String?
        var AbstractSource: String?
        var AbstractURL: String?
        var Heading: String?
        var RelatedTopics: [RelatedTopic]?

        struct RelatedTopic: Decodable {
            var Text: String?
            var FirstURL: String?
            var Result: String?
        }
    }

    /// Search using DuckDuckGo Instant Answer API (free, no key required)
    static func search(query: String) async throws -> [SearchResult] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1&skip_disambig=1") else {
            return []
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return []
        }

        let ddg = try JSONDecoder().decode(DuckDuckGoResponse.self, from: data)
        var results: [SearchResult] = []

        // Abstract result
        if let abstract = ddg.AbstractText, !abstract.isEmpty,
           let heading = ddg.Heading, let abstractURL = ddg.AbstractURL {
            results.append(SearchResult(
                title: heading,
                url: abstractURL,
                snippet: abstract
            ))
        }

        // Related topics
        if let topics = ddg.RelatedTopics {
            for topic in topics.prefix(5) {
                if let text = topic.Text, let url = topic.FirstURL {
                    let title = text.prefix(80).description
                    results.append(SearchResult(
                        title: title,
                        url: url,
                        snippet: text
                    ))
                }
            }
        }

        return results
    }

    /// Format search results as context for the model
    static func formatForContext(_ results: [SearchResult], query: String) -> String {
        guard !results.isEmpty else {
            return "[Web search for \"\(query)\" returned no results.]"
        }

        var lines: [String] = ["[Web search results for \"\(query)\":]"]
        for (idx, result) in results.prefix(5).enumerated() {
            lines.append("\(idx + 1). \(result.title)")
            lines.append("   URL: \(result.url)")
            lines.append("   \(result.snippet)")
            lines.append("")
        }
        lines.append("[End of search results. Please use this information to help answer the user's question.]")
        return lines.joined(separator: "\n")
    }

    /// Check if message is a search request
    static func isSearchRequest(_ content: String) -> (Bool, String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("/search ") {
            let query = String(trimmed.dropFirst(8))
            return (true, query)
        }
        return (false, "")
    }
}
