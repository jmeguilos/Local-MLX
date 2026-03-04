import SwiftUI
#if canImport(WebKit)
import WebKit
#endif

// MARK: - LaTeX Block View

struct LaTeXBlockView: View {
    let latex: String

    @State private var renderedHeight: CGFloat = 60

    var body: some View {
        #if canImport(WebKit)
        LaTeXWebView(latex: latex, height: $renderedHeight)
            .frame(height: renderedHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.vertical, 4)
        #else
        // Fallback: show raw LaTeX in a code block style
        Text(latex)
            .font(.system(.body, design: .monospaced))
            .padding(12)
            .background(Color.codeBlockBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.vertical, 4)
        #endif
    }
}

// MARK: - LaTeX WebView (WKWebView wrapper)

#if canImport(WebKit)
#if os(macOS)
struct LaTeXWebView: NSViewRepresentable {
    let latex: String
    @Binding var height: CGFloat

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = katexHTML(for: latex)
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> LaTeXCoordinator {
        LaTeXCoordinator(height: $height)
    }
}
#else
struct LaTeXWebView: UIViewRepresentable {
    let latex: String
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
        let html = katexHTML(for: latex)
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> LaTeXCoordinator {
        LaTeXCoordinator(height: $height)
    }
}
#endif

class LaTeXCoordinator: NSObject, WKNavigationDelegate {
    @Binding var height: CGFloat

    init(height: Binding<CGFloat>) {
        _height = height
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] result, _ in
            if let h = result as? CGFloat {
                DispatchQueue.main.async {
                    self?.height = max(h + 16, 40)
                }
            }
        }
    }
}

private func katexHTML(for latex: String) -> String {
    let escaped = latex
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "'", with: "\\'")
        .replacingOccurrences(of: "\n", with: "\\n")
    return """
    <!DOCTYPE html>
    <html>
    <head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css">
    <script src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"></script>
    <style>
    body {
        margin: 8px;
        padding: 0;
        background: transparent;
        display: flex;
        justify-content: center;
        align-items: center;
    }
    @media (prefers-color-scheme: dark) {
        body { color: #e0e0e0; }
        .katex { color: #e0e0e0; }
    }
    @media (prefers-color-scheme: light) {
        body { color: #1a1a1a; }
    }
    </style>
    </head>
    <body>
    <div id="math"></div>
    <script>
    katex.render('\(escaped)', document.getElementById('math'), {
        displayMode: true,
        throwOnError: false
    });
    </script>
    </body>
    </html>
    """
}
#endif
