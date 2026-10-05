import SwiftUI

struct SidebarView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openSettings) private var openSettings
    @State private var accountToRemove: Account?

    var body: some View {
        @Bindable var store = store
        List(selection: $store.selection) {
            Section {
                Label("Overview", systemImage: "square.grid.2x2")
                    .tag(SidebarItem.overview)
                Label("All Inboxes", systemImage: "tray.full")
                    .badge(store.unreadCount(in: .inbox))
                    .tag(SidebarItem.inbox)
            }

            Section {
                ForEach(store.groups) { group in
                    Label {
                        Text(group.name)
                    } icon: {
                        GroupBadge(symbol: group.symbol, color: group.color.color, size: 20)
                    }
                    .badge(store.unreadCount(in: .group(group.id)))
                    .tag(SidebarItem.group(group.id))
                    .contextMenu {
                        Button("Edit Group…", systemImage: "pencil") { store.beginEditing(group) }
                        Divider()
                        Button("Delete Group…", systemImage: "trash", role: .destructive) { store.groupToDelete = group }
                    }
                }
                .onMove { store.moveGroups(from: $0, to: $1) }

                Label("Everything Else", systemImage: "tray")
                    .badge(store.unreadCount(in: .ungrouped))
                    .tag(SidebarItem.ungrouped)
            } header: {
                HStack {
                    Text("Groups")
                    Spacer()
                    Button("New Group", systemImage: "plus") { store.beginNewGroup() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .help("Create a new group")
                }
            }

            Section("Accounts") {
                ForEach(store.accounts) { account in
                    accountRow(account)
                }
                if !store.isDemo {
                    Button("Add Account…", systemImage: "plus") { openSettings() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .confirmationDialog(
            "Remove \(accountToRemove?.email ?? "")?",
            isPresented: Binding(get: { accountToRemove != nil }, set: { if !$0 { accountToRemove = nil } }),
            presenting: accountToRemove
        ) { account in
            Button("Remove Account", role: .destructive) { store.remove(account) }
        } message: { _ in
            Text("Mailroom forgets this account and its cached mail. Nothing changes in Gmail.")
        }
    }

    @ViewBuilder
    private func accountRow(_ account: Account) -> some View {
        let error = store.accountErrors[account.email]
        Label {
            HStack(spacing: 4) {
                Text(account.email).lineLimit(1).truncationMode(.middle)
                if let error {
                    Spacer(minLength: 0)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .help(error)
                }
            }
        } icon: {
            AvatarView(name: account.email, seed: account.email, size: 20)
        }
        .tag(SidebarItem.account(account.email))
        .contextMenu {
            if !store.isDemo {
                Button("Sign In Again", systemImage: "arrow.clockwise") {
                    store.signIn(loginHint: account.email)
                    openSettings()
                }
                Divider()
                Button("Remove Account…", systemImage: "trash", role: .destructive) { accountToRemove = account }
            }
        }
    }
}
