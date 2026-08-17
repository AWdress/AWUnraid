import SwiftUI
import WebKit

struct WebAdminView: View {
    let url: URL
    @State private var reloadToken = UUID()

    var body: some View {
        WebView(url: url, reloadToken: reloadToken)
            .background(AppTheme.background)
            .navigationTitle("Web 管理台")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { reloadToken = UUID() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
    }
}

private struct WebView: UIViewRepresentable {
    let url: URL
    let reloadToken: UUID

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastReloadToken != reloadToken else { return }
        context.coordinator.lastReloadToken = reloadToken
        webView.reload()
    }

    func makeCoordinator() -> Coordinator { Coordinator(reloadToken: reloadToken) }

    final class Coordinator {
        var lastReloadToken: UUID
        init(reloadToken: UUID) { self.lastReloadToken = reloadToken }
    }
}
