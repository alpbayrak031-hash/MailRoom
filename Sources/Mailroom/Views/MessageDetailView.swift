import SwiftUI
import WebKit

struct MessageDetailView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if let message = store.selectedMessage {
            VStack(spacing: 0) {
                header(message)
                Divider()
                bodyView(message)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .task(id: message.id) {
                store.markRead(message)
                await store.loadBody(for: message)
            }
        } else {
            ContentUnavailableView(
                "No Message Selected", systemImage: "envelope.open",
                description: Text("Choose a message to read it here.")
            )
        }
    }

    private func header(_ message: MailMessage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(message.subject)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 12) {
                AvatarView(name: message.senderDisplay, seed: message.fromAddress, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.senderDisplay).font(.headline)
                    Text(message.fromAddress)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("To \(message.account)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 12)
                Text(message.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ForEach(store.groups(for: message)) { group in
                    Button { store.selection = .group(group.id) } label: { GroupChip(group: group) }
                        .buttonStyle(.plain)
                        .help("Show \(group.name)")
                }
                Spacer(minLength: 8)
                Menu("Group Sender") {
                    MessageGroupingMenu(message: message)
                }
                .fixedSize()
                if !store.isDemo, let url = gmailURL(for: message) {
                    Link(destination: url) { Label("Open in Gmail", systemImage: "arrow.up.forward.square") }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private func bodyView(_ message: MailMessage) -> some View {
        switch store.bodies[message.id] {
        case .loaded(let body):
            MailWebView(body: body).id(message.id)
        case .failed(let error):
            ContentUnavailableView {
                Label("Couldn't Load This Message", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") { Task { await store.loadBody(for: message) } }
            }
        case .loading, nil:
            ProgressView()
        }
    }

    private func gmailURL(for message: MailMessage) -> URL? {
        var components = URLComponents(string: "https://mail.google.com/mail/")
        components?.queryItems = [URLQueryItem(name: "authuser", value: message.account)]
        components?.fragment = "inbox/\(message.threadID)"
        return components?.url
    }
}

/// Renders a message body with scripts disabled. Links open in the default browser.
struct MailWebView: NSViewRepresentable {
    let body: MailBody

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(document, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    private var document: String {
        if let html = body.html {
            // Rich mail is authored for a white page, so it keeps one in dark mode too.
            return """
            <meta name="color-scheme" content="light only">
            <style>html{background:#fff}body{margin:16px 20px;font-family:-apple-system,sans-serif}img{max-width:100%;height:auto}</style>
            \(html)
            """
        }
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="color-scheme" content="light dark">
        <style>body{font:14px/1.55 -apple-system,sans-serif;margin:20px;white-space:pre-wrap;overflow-wrap:anywhere}</style>
        </head><body>\(MailParsing.escapeHTML(body.text ?? ""))</body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(
            _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated else {
                decisionHandler(.allow)
                return
            }
            if let url = navigationAction.request.url, ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }
}
