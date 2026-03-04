import SwiftUI
#if canImport(WebKit)
import WebKit
#endif

// MARK: - Mermaid Block View

struct MermaidBlockView: View {
    let code: String

    @State private var renderedHeight: CGFloat = 200

    var body: some View {
        #if canImport(WebKit)
        MermaidWebView(code: code, height: $renderedHeight)
            .frame(height: renderedHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.vertical, 4)
        #else
        // Fallback: show raw mermaid code
        CodeBlockView(language: "mermaid", code: code)
        #endif
    }
}

// MARK: - Mermaid WebView

#if canImport(WebKit)
#if os(macOS)
struct MermaidWebView: NSViewRepresentable {
    let code: String
    @Binding var height: CGFloat

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = mermaidHTML(for: code)
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> MermaidCoordinator {
        MermaidCoordinator(height: $height)
    }
}
#else
struct MermaidWebView: UIViewRepresentable {
    let code: String
    @Binding var height: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let html = mermaidHTML(for: code)
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> MermaidCoordinator {
        MermaidCoordinator(height: $height)
    }
}
#endif

class MermaidCoordinator: NSObject, WKNavigationDelegate {
    @Binding var height: CGFloat

    init(height: Binding<CGFloat>) {
        _height = height
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] result, _ in
                if let h = result as? CGFloat {
                    DispatchQueue.main.async {
                        self?.height = max(h + 16, 100)
                    }
                }
            }
        }
    }
}

private func mermaidHTML(for code: String) -> String {
    let escaped = code
        .replacingOccurrences(of: "`", with: "\\`")
        .replacingOccurrences(of: "${", with: "\\${")
    return """
    <!DOCTYPE html>
    <html>
    <head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
    <style>
    body {
        margin: 8px;
        padding: 0;
        background: transparent;
        display: flex;
        justify-content: center;
    }
    @media (prefers-color-scheme: dark) {
        body { color: #e0e0e0; }
    }
    </style>
    </head>
    <body>
    <pre class="mermaid">
    \(escaped)
    </pre>
    <script>
    mermaid.initialize({
        startOnLoad: true,
        theme: window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'default'
    });
    </script>
    </body>
    </html>
    """
}
#endif
