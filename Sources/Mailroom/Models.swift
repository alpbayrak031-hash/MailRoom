import SwiftUI

struct Account: Identifiable, Codable, Hashable {
    var email: String
    var id: String { email }
}

struct MailMessage: Identifiable, Codable, Hashable {
    /// "<account>/<gmail id>" so the same Gmail id in two accounts never collides.
    var id: String
    var gmailID: String
    var threadID: String
    var account: String
    var fromName: String
    var fromAddress: String
    var to: String
    var subject: String
    var snippet: String
    var date: Date
    var isUnread: Bool

    var senderDisplay: String { fromName.isEmpty ? fromAddress : fromName }

    var senderDomain: String {
        guard let at = fromAddress.lastIndex(of: "@") else { return "" }
        return String(fromAddress[fromAddress.index(after: at)...]).lowercased()
    }

    var recipientAddresses: [String] {
        to.split(separator: ",").map { MailParsing.parseAddress(String($0)).address } + [account.lowercased()]
    }
}

struct MailBody: Hashable {
    var html: String?
    var text: String?
}

// MARK: - Groups

struct MailRule: Identifiable, Codable, Hashable {
    enum Field: String, Codable, CaseIterable, Identifiable {
        case from, domain, subject, to
        var id: String { rawValue }
        var label: String {
            switch self {
            case .from: "Sender"
            case .domain: "Sender domain"
            case .subject: "Subject"
            case .to: "Recipient"
            }
        }
        var placeholder: String {
            switch self {
            case .from: "name or address"
            case .domain: "example.com"
            case .subject: "words in the subject"
            case .to: "you@gmail.com"
            }
        }
    }

    enum Op: String, Codable, CaseIterable, Identifiable {
        case contains, equals, startsWith, endsWith
        var id: String { rawValue }
        var label: String {
            switch self {
            case .contains: "contains"
            case .equals: "is"
            case .startsWith: "starts with"
            case .endsWith: "ends with"
            }
        }
    }

    var id = UUID()
    var field: Field = .from
    var op: Op = .contains
    var value: String = ""

    var trimmedValue: String { value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    var isComplete: Bool { !trimmedValue.isEmpty }

    func matches(_ message: MailMessage) -> Bool {
        let needle = trimmedValue
        guard !needle.isEmpty else { return false }
        let candidates: [String]
        switch field {
        case .from: candidates = [message.fromAddress, message.fromName]
        case .domain: candidates = [message.senderDomain]
        case .subject: candidates = [message.subject]
        case .to: candidates = message.recipientAddresses
        }
        return candidates.contains { raw in
            let haystack = raw.lowercased()
            switch op {
            case .contains: return haystack.contains(needle)
            case .equals: return haystack == needle
            case .startsWith: return haystack.hasPrefix(needle)
            case .endsWith: return haystack.hasSuffix(needle)
            }
        }
    }

    var summary: String { "\(field.label) \(op.label) “\(value.trimmingCharacters(in: .whitespaces))”" }
}

enum GroupColor: String, Codable, CaseIterable, Identifiable {
    case red, orange, yellow, green, mint, teal, blue, indigo, purple, pink, brown, gray
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .brown: .brown
        case .gray: .gray
        }
    }
}

struct MailGroup: Identifiable, Codable, Hashable {
    enum Mode: String, Codable, CaseIterable, Identifiable {
        case any, all
        var id: String { rawValue }
    }

    var id = UUID()
    var name: String
    var symbol: String = "tag.fill"
    var color: GroupColor = .blue
    var mode: Mode = .any
    var rules: [MailRule] = []

    func matches(_ message: MailMessage) -> Bool {
        let active = rules.filter(\.isComplete)
        guard !active.isEmpty else { return false }
        switch mode {
        case .any: return active.contains { $0.matches(message) }
        case .all: return active.allSatisfy { $0.matches(message) }
        }
    }

    static let symbols = [
        "graduationcap.fill", "building.columns.fill", "book.fill", "person.2.fill",
        "briefcase.fill", "cart.fill", "creditcard.fill", "airplane",
        "gamecontroller.fill", "newspaper.fill", "bell.fill", "star.fill",
        "heart.fill", "house.fill", "chevron.left.forwardslash.chevron.right", "music.note",
        "tag.fill", "envelope.fill", "bubble.left.fill", "calendar",
        "dollarsign.circle.fill", "shippingbox.fill", "sparkles", "folder.fill",
    ]

    static let defaults: [MailGroup] = [
        MailGroup(
            name: "Google Classroom", symbol: "graduationcap.fill", color: .green,
            rules: [MailRule(field: .from, op: .contains, value: "classroom.google.com")]
        ),
        // Staff write from the bare school domain; students from the "my." subdomain.
        MailGroup(
            name: "UAA Announcements", symbol: "bell.fill", color: .orange,
            rules: [MailRule(field: .from, op: .endsWith, value: "@uaa.k12.tr")]
        ),
        MailGroup(
            name: "UAA Students", symbol: "person.2.fill", color: .indigo,
            rules: [MailRule(field: .from, op: .endsWith, value: "@my.uaa.k12.tr")]
        ),
    ]
}

struct GroupDraft: Identifiable {
    var group: MailGroup
    var isNew: Bool
    var id: UUID { group.id }
}

enum SidebarItem: Hashable {
    case overview
    case inbox
    case group(UUID)
    case ungrouped
    case account(String)
}

// MARK: - Helpers

extension String {
    /// Deterministic across launches, unlike `hashValue`.
    var stableHash: Int {
        var hash: UInt64 = 5381
        for scalar in unicodeScalars { hash = (hash &* 33) &+ UInt64(scalar.value) }
        return Int(hash % UInt64(Int.max))
    }

    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
