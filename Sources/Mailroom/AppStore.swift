import AppKit
import Observation
import SwiftUI

enum BodyState {
    case loading
    case loaded(MailBody)
    case failed(String)
}

struct SenderSuggestion: Identifiable {
    var rule: MailRule
    var title: String
    var count: Int
    var id: String { title }
}

@MainActor @Observable
final class AppStore {
    static let inboxLimit = 300

    var accounts: [Account] = []
    var messages: [MailMessage] = [] { didSet { reindex() } }
    var groups: [MailGroup] = [] { didSet { reindex() } }
    var selection: SidebarItem? = .overview
    var selectedMessageID: MailMessage.ID?
    var searchText = ""
    var draft: GroupDraft?
    /// Set to ask for confirmation before a group is deleted.
    var groupToDelete: MailGroup?

    var config = OAuthConfig()
    var isDemo = false
    var isSyncing = false
    var isSigningIn = false
    var signInError: String?
    var accountErrors: [String: String] = [:]
    var lastSync: Date?
    var bodies: [String: BodyState] = [:]

    /// Ids of messages opened in Mailroom. Gmail is never told, so they can still be unread there.
    private(set) var locallyRead: Set<String> = []

    /// Message id → ids of the groups it belongs to, in sidebar order.
    private(set) var membership: [String: [UUID]] = [:]

    @ObservationIgnored private var managers: [String: TokenManager] = [:]
    @ObservationIgnored private var signInTask: Task<Void, Never>?

    init(demo: Bool = false) {
        config.clientID = UserDefaults.standard.string(forKey: "googleClientID") ?? ""
        groups = Storage.load([MailGroup].self, from: "groups.json") ?? MailGroup.defaults
        if demo {
            enterDemo()
        } else {
            config.clientSecret = Keychain.get("client-secret") ?? ""
            loadSavedMail()
        }
    }

    private func loadSavedMail() {
        accounts = Storage.load([Account].self, from: "accounts.json") ?? []
        locallyRead = Set(Storage.load([String].self, from: "read.json") ?? [])
        messages = (Storage.load([MailMessage].self, from: "cache.json") ?? []).map { message in
            var message = message
            message.isUnread = message.isUnread && !locallyRead.contains(message.id)
            return message
        }
    }

    // MARK: - Derived state

    var needsOnboarding: Bool { accounts.isEmpty && !isDemo }
    var currentSelection: SidebarItem { selection ?? .overview }
    var selectedMessage: MailMessage? { messages.first { $0.id == selectedMessageID } }
    var unreadTotal: Int { messages.count { $0.isUnread } }

    var selectedGroup: MailGroup? {
        guard case .group(let id) = currentSelection else { return nil }
        return groups.first { $0.id == id }
    }

    private func reindex() {
        membership = Dictionary(
            messages.map { message in (message.id, groups.filter { $0.matches(message) }.map(\.id)) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func groups(for message: MailMessage) -> [MailGroup] {
        let ids = membership[message.id] ?? []
        return groups.filter { ids.contains($0.id) }
    }

    func messages(in item: SidebarItem) -> [MailMessage] {
        switch item {
        case .overview, .inbox: messages
        case .group(let id): messages.filter { membership[$0.id]?.contains(id) ?? false }
        case .ungrouped: messages.filter { membership[$0.id]?.isEmpty ?? true }
        case .account(let email): messages.filter { $0.account == email }
        }
    }

    func unreadCount(in item: SidebarItem) -> Int {
        messages(in: item).count { $0.isUnread }
    }

    var visibleMessages: [MailMessage] {
        let scoped = messages(in: currentSelection)
        let query = searchText.trimmed
        guard !query.isEmpty else { return scoped }
        return scoped.filter {
            $0.senderDisplay.localizedStandardContains(query)
                || $0.fromAddress.localizedStandardContains(query)
                || $0.subject.localizedStandardContains(query)
                || $0.snippet.localizedStandardContains(query)
        }
    }

    func title(for item: SidebarItem) -> String {
        switch item {
        case .overview: "Overview"
        case .inbox: "All Inboxes"
        case .group(let id): groups.first { $0.id == id }?.name ?? "Group"
        case .ungrouped: "Everything Else"
        case .account(let email): email
        }
    }

    /// Senders that show up repeatedly in ungrouped mail. Shared mail providers
    /// are suggested per address, everything else per domain.
    var suggestions: [SenderSuggestion] {
        let shared: Set<String> = [
            "gmail.com", "googlemail.com", "outlook.com", "hotmail.com", "yahoo.com", "icloud.com", "me.com",
        ]
        var counts: [String: (rule: MailRule, count: Int)] = [:]
        for message in messages(in: .ungrouped) where !message.fromAddress.isEmpty {
            let domain = message.senderDomain
            let rule = shared.contains(domain) || domain.isEmpty
                ? MailRule(field: .from, op: .equals, value: message.fromAddress)
                : MailRule(field: .domain, op: .equals, value: domain)
            counts[rule.value, default: (rule, 0)].count += 1
        }
        return counts
            .filter { $0.value.count >= 2 }
            .map { SenderSuggestion(rule: $0.value.rule, title: $0.key, count: $0.value.count) }
            .sorted { ($0.count, $1.title) > ($1.count, $0.title) }
            .prefix(6)
            .map { $0 }
    }

    // MARK: - Groups

    func beginNewGroup(name: String = "", rule: MailRule? = nil) {
        let used = Set(groups.map(\.color))
        let color = GroupColor.allCases.first { !used.contains($0) } ?? .blue
        draft = GroupDraft(
            group: MailGroup(name: name, color: color, rules: [rule ?? MailRule()]),
            isNew: true
        )
    }

    func beginEditing(_ group: MailGroup) {
        draft = GroupDraft(group: group, isNew: false)
    }

    func commit(_ group: MailGroup) {
        var group = group
        group.name = group.name.trimmed.isEmpty ? "Untitled Group" : group.name.trimmed
        group.rules = group.rules.filter(\.isComplete)
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups[index] = group
        } else {
            groups.append(group)
            selection = .group(group.id)
        }
        saveGroups()
    }

    func delete(_ group: MailGroup) {
        if selection == .group(group.id) { selection = .overview }
        groups.removeAll { $0.id == group.id }
        saveGroups()
    }

    func moveGroups(from source: IndexSet, to destination: Int) {
        groups.move(fromOffsets: source, toOffset: destination)
        saveGroups()
    }

    /// Groups a sender can be added to without changing what they already match.
    var groupsAcceptingSenders: [MailGroup] {
        groups.filter { $0.mode == .any || $0.rules.count <= 1 }
    }

    func addSender(_ address: String, to group: MailGroup) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[index].mode = .any
        groups[index].rules.append(MailRule(field: .from, op: .equals, value: address))
        saveGroups()
    }

    private func saveGroups() {
        Storage.save(groups, to: "groups.json")
    }

    // MARK: - Read state

    func markRead(_ message: MailMessage) {
        guard let index = messages.firstIndex(where: { $0.id == message.id }), messages[index].isUnread else { return }
        messages[index].isUnread = false
        locallyRead.insert(message.id)
        saveReadState()
    }

    /// Only a read that happened in Mailroom can be undone; Gmail's own state isn't ours to change.
    func canMarkUnread(_ message: MailMessage) -> Bool {
        !message.isUnread && locallyRead.contains(message.id)
    }

    func markUnread(_ message: MailMessage) {
        guard canMarkUnread(message), let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages[index].isUnread = true
        locallyRead.remove(message.id)
        saveReadState()
    }

    private func saveReadState() {
        guard !isDemo else { return }
        Storage.save(locallyRead.sorted(), to: "read.json")
    }

    // MARK: - Accounts

    func saveConfig() {
        UserDefaults.standard.set(config.clientID.trimmed, forKey: "googleClientID")
        try? Keychain.set(config.clientSecret.trimmed, for: "client-secret")
        managers.removeAll()
    }

    func signIn(loginHint: String? = nil) {
        guard !isSigningIn else { return }
        signInError = nil
        isSigningIn = true
        saveConfig()
        signInTask = Task {
            defer { isSigningIn = false }
            do {
                let tokens = try await GoogleOAuth.signIn(config: config, loginHint: loginHint)
                NSApp.activate(ignoringOtherApps: true)
                guard let refreshToken = tokens.refreshToken else { throw OAuthError.noRefreshToken }
                let email = try await GmailClient.profileEmail(accessToken: tokens.accessToken)
                try Keychain.set(refreshToken, for: "refresh:\(email)")
                if isDemo { leaveDemo() }
                managers[email] = TokenManager(config: config, refreshToken: refreshToken, initial: tokens)
                accountErrors[email] = nil
                let account = Account(email: email)
                if !accounts.contains(account) { accounts.append(account) }
                Storage.save(accounts, to: "accounts.json")
                await sync(account)
                Storage.save(messages, to: "cache.json")
            } catch is CancellationError {
            } catch {
                NSApp.activate(ignoringOtherApps: true)
                signInError = error.localizedDescription
            }
        }
    }

    func cancelSignIn() {
        signInTask?.cancel()
    }

    func remove(_ account: Account) {
        Keychain.remove("refresh:\(account.email)")
        managers[account.email] = nil
        accountErrors[account.email] = nil
        accounts.removeAll { $0 == account }
        messages.removeAll { $0.account == account.email }
        if selection == .account(account.email) { selection = .overview }
        guard !isDemo else { return }
        Storage.save(accounts, to: "accounts.json")
        Storage.save(messages, to: "cache.json")
    }

    private func client(for email: String) throws -> GmailClient {
        if let manager = managers[email] { return GmailClient(account: email, tokens: manager) }
        guard let refreshToken = Keychain.get("refresh:\(email)") else { throw OAuthError.needsSignIn }
        let manager = TokenManager(config: config, refreshToken: refreshToken)
        managers[email] = manager
        return GmailClient(account: email, tokens: manager)
    }

    // MARK: - Sync

    func refresh() async {
        guard !isDemo, !isSyncing, !accounts.isEmpty else { return }
        isSyncing = true
        defer { isSyncing = false }
        await withTaskGroup(of: Void.self) { group in
            for account in accounts {
                group.addTask { await self.sync(account) }
            }
        }
        lastSync = Date()
        // Forget read marks for mail that has left the inbox.
        locallyRead.formIntersection(messages.map(\.id))
        saveReadState()
        Storage.save(messages, to: "cache.json")
    }

    private func sync(_ account: Account) async {
        let email = account.email
        do {
            let client = try client(for: email)
            async let inbox = client.listIDs(query: "in:inbox", limit: Self.inboxLimit)
            async let unreadIDs = client.listIDs(query: "in:inbox is:unread", limit: Self.inboxLimit)
            let ids = try await inbox
            let unread = Set(try await unreadIDs)

            var known = Dictionary(
                messages.filter { $0.account == email }.map { ($0.gmailID, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            func publish() {
                let current = ids.compactMap { id -> MailMessage? in
                    guard var message = known[id] else { return nil }
                    message.isUnread = unread.contains(id) && !locallyRead.contains(message.id)
                    return message
                }
                messages = (messages.filter { $0.account != email } + current).sorted { $0.date > $1.date }
            }

            publish()
            for chunk in ids.filter({ known[$0] == nil }).chunked(24) {
                for message in try await client.metadata(ids: chunk) { known[message.gmailID] = message }
                guard accounts.contains(account) else { return }
                publish()
            }
            accountErrors[email] = nil
        } catch is CancellationError {
        } catch {
            accountErrors[email] = error.localizedDescription
        }
    }

    func loadBody(for message: MailMessage) async {
        if case .loaded = bodies[message.id] { return }
        if isDemo {
            bodies[message.id] = .loaded(SampleData.body(for: message))
            return
        }
        bodies[message.id] = .loading
        do {
            let body = try await client(for: message.account).body(id: message.gmailID)
            bodies[message.id] = .loaded(body)
        } catch {
            bodies[message.id] = .failed(error.localizedDescription)
        }
    }

    // MARK: - Sample data

    func enterDemo() {
        isDemo = true
        locallyRead = []
        accounts = SampleData.accounts
        messages = SampleData.messages()
        selection = .overview
    }

    func leaveDemo() {
        isDemo = false
        bodies.removeAll()
        loadSavedMail()
        selection = .overview
    }
}

enum Storage {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Mailroom", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func load<T: Decodable>(_ type: T.Type, from file: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(file)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, to file: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: directory.appendingPathComponent(file), options: .atomic)
    }
}
