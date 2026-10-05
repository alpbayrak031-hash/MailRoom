import AppKit
import CryptoKit
import Foundation
import Network

struct OAuthConfig: Equatable, Sendable {
    var clientID = ""
    var clientSecret = ""

    var isUsable: Bool { !clientID.trimmed.isEmpty }
    var looksValid: Bool { clientID.trimmed.hasSuffix(".apps.googleusercontent.com") }
}

struct TokenSet: Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiry: Date
    var scope: String
}

enum OAuthError: LocalizedError {
    case denied(String)
    case stateMismatch
    case missingScope
    case noRefreshToken
    case needsSignIn
    case server(String)

    var errorDescription: String? {
        switch self {
        case .denied(let reason):
            reason == "access_denied" ? "Sign-in was cancelled." : "Google refused the sign-in (\(reason))."
        case .stateMismatch:
            "The sign-in response didn't match the request. Please try again."
        case .missingScope:
            "Mailroom needs permission to read your Gmail. Tick the Gmail box on Google's consent screen and try again."
        case .noRefreshToken:
            "Google didn't return a long-lived token. Remove Mailroom at myaccount.google.com/permissions and sign in again."
        case .needsSignIn:
            "Your sign-in expired. Sign in again to keep syncing."
        case .server(let message):
            message
        }
    }
}

enum GoogleOAuth {
    static let scope = "https://www.googleapis.com/auth/gmail.readonly"
    private static let authEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    private static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    /// Authorization-code flow with PKCE. Google redirects the browser to a
    /// one-shot listener on 127.0.0.1, which is what its "Desktop app" clients expect.
    static func signIn(config: OAuthConfig, loginHint: String? = nil) async throws -> TokenSet {
        let receiver = LoopbackReceiver()
        let port = try await receiver.start()
        defer { receiver.stop() }

        let redirectURI = "http://127.0.0.1:\(port)"
        let verifier = randomURLSafe(byteCount: 48)
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = randomURLSafe(byteCount: 18)

        var components = URLComponents(string: authEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID.trimmed),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: loginHint == nil ? "consent select_account" : "consent"),
        ]
        if let loginHint {
            components.queryItems?.append(URLQueryItem(name: "login_hint", value: loginHint))
        }
        let url = components.url!
        _ = await MainActor.run { NSWorkspace.shared.open(url) }

        let params = try await receiver.waitForCallback()
        if let error = params["error"] { throw OAuthError.denied(error) }
        guard params["state"] == state, let code = params["code"] else { throw OAuthError.stateMismatch }

        let tokens = try await requestToken(config: config, fields: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": verifier,
        ])
        guard tokens.scope.split(separator: " ").contains(Substring(scope)) else { throw OAuthError.missingScope }
        return tokens
    }

    static func refresh(config: OAuthConfig, refreshToken: String) async throws -> TokenSet {
        var tokens = try await requestToken(config: config, fields: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])
        tokens.refreshToken = tokens.refreshToken ?? refreshToken
        return tokens
    }

    private struct TokenResponse: Decodable {
        let access_token: String?
        let refresh_token: String?
        let expires_in: Double?
        let scope: String?
        let error: String?
        let error_description: String?
    }

    private static func requestToken(config: OAuthConfig, fields: [String: String]) async throws -> TokenSet {
        var fields = fields
        fields["client_id"] = config.clientID.trimmed
        if !config.clientSecret.trimmed.isEmpty { fields["client_secret"] = config.clientSecret.trimmed }

        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(
            fields.map { "\(formEncode($0.key))=\(formEncode($0.value))" }.joined(separator: "&").utf8
        )

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let response = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw OAuthError.server("Google returned an unreadable sign-in response.")
        }
        if let error = response.error {
            switch error {
            case "invalid_grant":
                throw OAuthError.needsSignIn
            case "invalid_client":
                throw OAuthError.server(
                    "Google rejected the client ID or secret. Check both in Settings — a “Desktop app” client needs its secret too."
                )
            default:
                throw OAuthError.server(response.error_description ?? error)
            }
        }
        guard let access = response.access_token else {
            throw OAuthError.server("Google didn't return an access token.")
        }
        return TokenSet(
            accessToken: access,
            refreshToken: response.refresh_token,
            expiry: Date().addingTimeInterval(response.expires_in ?? 3600),
            scope: response.scope ?? ""
        )
    }

    private static func randomURLSafe(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncode(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}

/// Hands out a fresh access token per account, refreshing at most once at a time.
actor TokenManager {
    private let config: OAuthConfig
    private let refreshToken: String
    private var accessToken: String?
    private var expiry = Date.distantPast
    private var refreshTask: Task<TokenSet, Error>?

    init(config: OAuthConfig, refreshToken: String, initial: TokenSet? = nil) {
        self.config = config
        self.refreshToken = refreshToken
        self.accessToken = initial?.accessToken
        self.expiry = initial?.expiry ?? .distantPast
    }

    func validToken() async throws -> String {
        if let accessToken, expiry.timeIntervalSinceNow > 60 { return accessToken }
        if let refreshTask { return try await refreshTask.value.accessToken }
        let task = Task { [config, refreshToken] in
            try await GoogleOAuth.refresh(config: config, refreshToken: refreshToken)
        }
        refreshTask = task
        defer { refreshTask = nil }
        let tokens = try await task.value
        accessToken = tokens.accessToken
        expiry = tokens.expiry
        return tokens.accessToken
    }

    func invalidate() {
        accessToken = nil
    }
}

/// Minimal one-shot HTTP listener bound to the loopback interface that captures
/// the query string of Google's redirect.
final class LoopbackReceiver: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.alpgbayrak.Mailroom.oauth")
    private var listener: NWListener?
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var pending: Result<[String: String], Error>?
    private var startContinuation: CheckedContinuation<UInt16, Error>?

    func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }

        return try await withCheckedThrowingContinuation { continuation in
            // State updates arrive on `queue`, which also guards `startContinuation`.
            startContinuation = continuation
            listener.stateUpdateHandler = { [weak self] state in
                guard let self, let continuation = self.startContinuation else { return }
                switch state {
                case .ready:
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error), .waiting(let error):
                    continuation.resume(throwing: error)
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                default:
                    return
                }
                self.startContinuation = nil
            }
            listener.start(queue: queue)
        }
    }

    func waitForCallback() async throws -> [String: String] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    if let pending = self.pending {
                        continuation.resume(with: pending)
                    } else {
                        self.continuation = continuation
                    }
                }
            }
        } onCancel: {
            queue.async { self.deliver(.failure(CancellationError())) }
        }
    }

    func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
        }
    }

    private func deliver(_ result: Result<[String: String], Error>) {
        guard pending == nil else { return }
        pending = result
        continuation?.resume(with: result)
        continuation = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8),
                  let requestLine = request.split(separator: "\r\n").first
            else {
                connection.cancel()
                return
            }
            let parts = requestLine.split(separator: " ")
            let target = parts.count > 1 ? String(parts[1]) : "/"
            let items = URLComponents(string: "http://127.0.0.1\(target)")?.queryItems ?? []
            let params = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })

            guard params["code"] != nil || params["error"] != nil else {
                self.respond(on: connection, status: "404 Not Found", body: "")
                return
            }
            let succeeded = params["code"] != nil
            self.respond(on: connection, status: "200 OK", body: Self.page(succeeded: succeeded))
            self.deliver(.success(params))
        }
    }

    private func respond(on connection: NWConnection, status: String, body: String) {
        let payload = Data(body.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func page(succeeded: Bool) -> String {
        let title = succeeded ? "You're signed in" : "Sign-in didn't finish"
        let detail = succeeded
            ? "You can close this tab and return to Mailroom."
            : "Close this tab and try again from Mailroom."
        return """
        <!doctype html><html><head><meta charset="utf-8"><title>Mailroom</title>
        <meta name="color-scheme" content="light dark">
        <style>
        body{font:16px -apple-system,system-ui,sans-serif;display:grid;place-items:center;height:100vh;margin:0}
        main{text-align:center}h1{font-size:28px;margin:0 0 8px}p{opacity:.65;margin:0}
        </style></head><body><main><h1>\(title)</h1><p>\(detail)</p></main></body></html>
        """
    }
}
