import Foundation

enum GmailError: LocalizedError {
    case http(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .http(_, let message): message
        }
    }
}

struct GmailClient: Sendable {
    let account: String
    let tokens: TokenManager

    private static let base = "https://gmail.googleapis.com/gmail/v1/users/me/"

    // MARK: Requests

    static func profileEmail(accessToken: String) async throws -> String {
        struct Profile: Decodable { let emailAddress: String }
        let (data, response) = try await send(path: "profile", query: [], token: accessToken)
        try check(data: data, response: response)
        return try JSONDecoder().decode(Profile.self, from: data).emailAddress.lowercased()
    }

    private static func send(path: String, query: [URLQueryItem], token: String) async throws -> (Data, HTTPURLResponse) {
        var components = URLComponents(string: base + path)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, response as! HTTPURLResponse)
    }

    private static func check(data: Data, response: HTTPURLResponse) throws {
        guard !(200..<300).contains(response.statusCode) else { return }
        struct Envelope: Decodable {
            struct Body: Decodable { let message: String? }
            let error: Body?
        }
        let message = (try? JSONDecoder().decode(Envelope.self, from: data))?.error?.message
        throw GmailError.http(
            status: response.statusCode,
            message: message ?? "Gmail returned an error (\(response.statusCode))."
        )
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var refreshedAfter401 = false
        var attempt = 0
        while true {
            let token = try await tokens.validToken()
            let (data, response) = try await Self.send(path: path, query: query, token: token)
            let status = response.statusCode
            if status == 401, !refreshedAfter401 {
                refreshedAfter401 = true
                await tokens.invalidate()
                continue
            }
            let rateLimited = status == 429 || (status == 403 && String(decoding: data, as: UTF8.self).contains("ateLimitExceeded"))
            if (rateLimited || status >= 500), attempt < 4 {
                attempt += 1
                try await Task.sleep(for: .milliseconds(400 * (1 << attempt)))
                continue
            }
            try Self.check(data: data, response: response)
            return try JSONDecoder().decode(T.self, from: data)
        }
    }

    // MARK: Listing

    private struct ListResponse: Decodable {
        struct Ref: Decodable { let id: String }
        let messages: [Ref]?
        let nextPageToken: String?
    }

    /// Newest-first message ids matching a Gmail search query.
    func listIDs(query: String, limit: Int) async throws -> [String] {
        var ids: [String] = []
        var pageToken: String?
        repeat {
            var items = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "maxResults", value: String(min(500, limit - ids.count))),
            ]
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let page: ListResponse = try await get("messages", query: items)
            ids += (page.messages ?? []).map(\.id)
            pageToken = page.nextPageToken
        } while pageToken != nil && ids.count < limit
        return Array(ids.prefix(limit))
    }

    // MARK: Messages

    private struct RawMessage: Decodable {
        let id: String
        let threadId: String
        let labelIds: [String]?
        let snippet: String?
        let internalDate: String?
        let payload: Part?
    }

    private struct Part: Decodable {
        struct Header: Decodable { let name: String; let value: String }
        struct Body: Decodable { let data: String? }
        let mimeType: String?
        let filename: String?
        let headers: [Header]?
        let body: Body?
        let parts: [Part]?

        func header(_ name: String) -> String? {
            headers?.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
    }

    func metadata(id: String) async throws -> MailMessage {
        let raw: RawMessage = try await get("messages/\(id)", query: [
            URLQueryItem(name: "format", value: "metadata"),
            URLQueryItem(name: "metadataHeaders", value: "From"),
            URLQueryItem(name: "metadataHeaders", value: "To"),
            URLQueryItem(name: "metadataHeaders", value: "Subject"),
        ])
        let from = MailParsing.parseAddress(raw.payload?.header("From") ?? "")
        let subject = MailParsing.decodeEncodedWords(raw.payload?.header("Subject") ?? "").trimmed
        let millis = Double(raw.internalDate ?? "") ?? 0
        return MailMessage(
            id: "\(account)/\(raw.id)",
            gmailID: raw.id,
            threadID: raw.threadId,
            account: account,
            fromName: from.name,
            fromAddress: from.address,
            to: MailParsing.decodeEncodedWords(raw.payload?.header("To") ?? ""),
            subject: subject.isEmpty ? "(no subject)" : subject,
            snippet: MailParsing.decodeEntities(raw.snippet ?? ""),
            date: Date(timeIntervalSince1970: millis / 1000),
            isUnread: raw.labelIds?.contains("UNREAD") ?? false
        )
    }

    /// Fetches metadata concurrently. Messages deleted since the listing are skipped.
    func metadata(ids: [String]) async throws -> [MailMessage] {
        try await withThrowingTaskGroup(of: MailMessage?.self) { group in
            for id in ids {
                group.addTask {
                    do {
                        return try await metadata(id: id)
                    } catch GmailError.http(status: 404, _) {
                        return nil
                    }
                }
            }
            var result: [MailMessage] = []
            for try await message in group {
                if let message { result.append(message) }
            }
            return result
        }
    }

    func body(id: String) async throws -> MailBody {
        let raw: RawMessage = try await get("messages/\(id)", query: [URLQueryItem(name: "format", value: "full")])
        var body = MailBody()
        if let payload = raw.payload { Self.collect(payload, into: &body) }
        if body.html == nil, body.text == nil { body.text = MailParsing.decodeEntities(raw.snippet ?? "") }
        return body
    }

    private static func collect(_ part: Part, into body: inout MailBody) {
        let type = (part.mimeType ?? "").lowercased()
        if type.hasPrefix("multipart/") {
            part.parts?.forEach { collect($0, into: &body) }
            return
        }
        guard (part.filename ?? "").isEmpty, let encoded = part.body?.data,
              let data = MailParsing.decodeBase64URL(encoded)
        else { return }
        let text = MailParsing.string(from: data, contentType: part.header("Content-Type"))
        if type == "text/html", body.html == nil {
            body.html = text
        } else if type == "text/plain", body.text == nil {
            body.text = text
        }
    }
}

enum MailParsing {
    /// Splits `"Jane Doe" <jane@example.com>` into its display name and address.
    static func parseAddress(_ raw: String) -> (name: String, address: String) {
        let value = decodeEncodedWords(raw).trimmed
        guard let open = value.lastIndex(of: "<"), let close = value.lastIndex(of: ">"), open < close else {
            return ("", value.lowercased())
        }
        let address = value[value.index(after: open)..<close].trimmingCharacters(in: .whitespaces).lowercased()
        let name = value[..<open]
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .replacingOccurrences(of: "\\\"", with: "\"")
        return (name, address)
    }

    static func decodeBase64URL(_ string: String) -> Data? {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        return Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
    }

    static func string(from data: Data, contentType: String?) -> String {
        if let contentType,
           let range = contentType.range(of: #"charset="?([^";\s]+)"#, options: [.regularExpression, .caseInsensitive]) {
            let name = contentType[range]
                .replacingOccurrences(of: "charset=", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if let decoded = String(data: data, encoding: encoding(named: name)) { return decoded }
        }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    private static func encoding(named name: String) -> String.Encoding {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return .utf8 }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
    }

    private static let encodedWord = try! NSRegularExpression(pattern: #"=\?([^?\s]+)\?([bBqQ])\?([^?\s]*)\?="#)
    private static let encodedWordGap = try! NSRegularExpression(pattern: #"(\?=)\s+(=\?)"#)

    /// RFC 2047 header decoding, e.g. `=?UTF-8?B?w5ZkZXY=?=` → `Ödev`.
    static func decodeEncodedWords(_ input: String) -> String {
        guard input.contains("=?") else { return input }
        let joined = encodedWordGap.stringByReplacingMatches(
            in: input, range: NSRange(input.startIndex..., in: input), withTemplate: "$1$2"
        )
        var output = ""
        var cursor = joined.startIndex
        for match in encodedWord.matches(in: joined, range: NSRange(joined.startIndex..., in: joined)) {
            guard let whole = Range(match.range, in: joined),
                  let charset = Range(match.range(at: 1), in: joined),
                  let kind = Range(match.range(at: 2), in: joined),
                  let payload = Range(match.range(at: 3), in: joined)
            else { continue }
            output += joined[cursor..<whole.lowerBound]
            let data: Data? = joined[kind].lowercased() == "b"
                ? Data(base64Encoded: String(joined[payload]), options: .ignoreUnknownCharacters)
                : decodeQ(String(joined[payload]))
            if let data, let decoded = String(data: data, encoding: encoding(named: String(joined[charset]))) {
                output += decoded
            } else {
                output += joined[whole]
            }
            cursor = whole.upperBound
        }
        output += joined[cursor...]
        return output
    }

    private static func decodeQ(_ string: String) -> Data {
        var data = Data()
        let bytes = Array(string.utf8)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "_") {
                data.append(0x20)
            } else if byte == UInt8(ascii: "="), index + 2 < bytes.count,
                      let value = UInt8(String(decoding: bytes[(index + 1)...(index + 2)], as: UTF8.self), radix: 16) {
                data.append(value)
                index += 2
            } else {
                data.append(byte)
            }
            index += 1
        }
        return data
    }

    private static let numericEntity = try! NSRegularExpression(pattern: #"&#(x?)([0-9a-fA-F]+);"#)

    /// Gmail snippets arrive HTML-escaped.
    static func decodeEntities(_ input: String) -> String {
        guard input.contains("&") else { return input }
        var text = input
        for (entity, replacement) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&nbsp;", " ")] {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        for match in numericEntity.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(match.range, in: text),
                  let digits = Range(match.range(at: 2), in: text),
                  let code = UInt32(text[digits], radix: match.range(at: 1).length > 0 ? 16 : 10),
                  let scalar = Unicode.Scalar(code)
            else { continue }
            text.replaceSubrange(whole, with: String(Character(scalar)))
        }
        return text.replacingOccurrences(of: "&amp;", with: "&")
    }

    static func escapeHTML(_ input: String) -> String {
        input
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
