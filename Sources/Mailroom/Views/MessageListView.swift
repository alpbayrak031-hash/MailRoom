import SwiftUI

struct MessageListView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        let messages = store.visibleMessages
        if messages.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $store.selectedMessageID) {
                ForEach(MailDate.buckets(messages)) { bucket in
                    Section(bucket.title) {
                        ForEach(bucket.messages) { message in
                            MessageRow(message: message, chips: chips(for: message))
                                .tag(message.id)
                                .contextMenu {
                                    if message.isUnread {
                                        Button("Mark as Read", systemImage: "envelope.open") { store.markRead(message) }
                                    } else if store.canMarkUnread(message) {
                                        Button("Mark as Unread", systemImage: "envelope.badge") { store.markUnread(message) }
                                    }
                                    Divider()
                                    MessageGroupingMenu(message: message)
                                }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    /// The group being viewed is implied, so its own chip is left out.
    private func chips(for message: MailMessage) -> [MailGroup] {
        store.groups(for: message).filter { store.currentSelection != .group($0.id) }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !store.searchText.trimmed.isEmpty {
            ContentUnavailableView.search(text: store.searchText)
        } else if store.isSyncing {
            ProgressView("Loading mail…")
        } else if case .group(let id) = store.currentSelection, let group = store.groups.first(where: { $0.id == id }) {
            ContentUnavailableView {
                Label("Nothing Here Yet", systemImage: group.symbol)
            } description: {
                Text("No mail in your inbox matches this group's rules.")
            } actions: {
                Button("Edit Rules…") { store.beginEditing(group) }
            }
        } else {
            ContentUnavailableView("No Mail", systemImage: "tray", description: Text("Your inbox is empty."))
        }
    }
}

struct MessageRow: View {
    let message: MailMessage
    let chips: [MailGroup]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(message.isUnread ? Color.accentColor : .clear)
                .frame(width: 8, height: 8)
                .padding(.top, 14)
                .accessibilityLabel(message.isUnread ? "Unread" : "")

            AvatarView(name: message.senderDisplay, seed: message.fromAddress, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(message.senderDisplay)
                        .font(.body.weight(message.isUnread ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(MailDate.short(message.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(message.subject)
                    .font(.callout.weight(message.isUnread ? .medium : .regular))
                    .lineLimit(1)
                Text(message.snippet)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if !chips.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(chips.prefix(3)) { GroupChip(group: $0) }
                    }
                    .padding(.top, 3)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

/// "Put this sender in a group" actions shared by the list's context menu and the detail header.
struct MessageGroupingMenu: View {
    @Environment(AppStore.self) private var store
    let message: MailMessage

    var body: some View {
        let targets = store.groupsAcceptingSenders
        if !targets.isEmpty {
            Menu("Add Sender to Group") {
                ForEach(targets) { group in
                    Button(group.name, systemImage: group.symbol) { store.addSender(message.fromAddress, to: group) }
                }
            }
        }
        Button("New Group from \(message.fromAddress)…", systemImage: "person.crop.circle.badge.plus") {
            store.beginNewGroup(
                name: message.senderDisplay,
                rule: MailRule(field: .from, op: .equals, value: message.fromAddress)
            )
        }
        if !message.senderDomain.isEmpty {
            Button("New Group from Everyone @\(message.senderDomain)…", systemImage: "at") {
                store.beginNewGroup(
                    name: message.senderDomain,
                    rule: MailRule(field: .from, op: .endsWith, value: "@\(message.senderDomain)")
                )
            }
        }
    }
}
