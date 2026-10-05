import SwiftUI

@main
struct MailroomApp: App {
    @State private var store = AppStore(demo: CommandLine.arguments.contains("--demo"))

    var body: some Scene {
        Window("Mailroom", id: "main") {
            RootView()
                .environment(store)
                .frame(minWidth: 980, minHeight: 620)
        }
        .defaultSize(width: 1320, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Group") {
                Button("New Group…") { store.beginNewGroup() }
                    .keyboardShortcut("n")
                    .disabled(store.needsOnboarding)
                Divider()
                Button("Edit Group…") {
                    if let group = store.selectedGroup { store.beginEditing(group) }
                }
                .keyboardShortcut("e")
                .disabled(store.selectedGroup == nil)
                Button("Delete Group…") { store.groupToDelete = store.selectedGroup }
                    .disabled(store.selectedGroup == nil)
            }
            CommandGroup(after: .sidebar) {
                Button("Refresh") { Task { await store.refresh() } }
                    .keyboardShortcut("r")
                    .disabled(store.isDemo || store.isSyncing)
            }
        }

        Settings {
            SettingsView().environment(store)
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Group {
            if store.needsOnboarding {
                WelcomeView()
            } else {
                MainView()
            }
        }
        .sheet(item: $store.draft) { draft in
            GroupEditorView(draft: draft)
        }
        .confirmationDialog(
            "Delete “\(store.groupToDelete?.name ?? "")”?",
            isPresented: Binding(get: { store.groupToDelete != nil }, set: { if !$0 { store.groupToDelete = nil } }),
            presenting: store.groupToDelete
        ) { group in
            Button("Delete Group", role: .destructive) { store.delete(group) }
        } message: { _ in
            Text("Only the group and its rules are removed. Your mail stays where it is.")
        }
        .task {
            // Sync on launch, then every five minutes while the window is open.
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }
}

struct MainView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 340)
        } detail: {
            VStack(spacing: 0) {
                if store.isDemo { demoBanner }
                if store.currentSelection == .overview {
                    OverviewView()
                } else {
                    HSplitView {
                        MessageListView()
                            .frame(minWidth: 320, idealWidth: 400, maxWidth: 560)
                        MessageDetailView()
                            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .searchable(text: $store.searchText, prompt: "Search mail")
                }
            }
            .onChange(of: store.selection) { store.selectedMessageID = nil }
            .navigationTitle(store.title(for: store.currentSelection))
            .navigationSubtitle(subtitle)
            .toolbar {
                if let group = store.selectedGroup {
                    ToolbarItem {
                        Button { store.beginEditing(group) } label: {
                            Label("Edit Group", systemImage: "slider.horizontal.3").labelStyle(.titleAndIcon)
                        }
                        .help("Change this group's name, colour, icon and rules")
                    }
                }
                ToolbarItem {
                    Button("New Group", systemImage: "plus") { store.beginNewGroup() }
                        .help("Create a new group")
                }
                ToolbarItem {
                    if store.isSyncing {
                        ProgressView().controlSize(.small).padding(.horizontal, 8)
                    } else {
                        Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.refresh() } }
                            .disabled(store.isDemo)
                            .help("Check for new mail")
                    }
                }
            }
        }
    }

    private var subtitle: String {
        let scoped = store.messages(in: store.currentSelection)
        let unread = scoped.count { $0.isUnread }
        let total = "\(scoped.count) \(scoped.count == 1 ? "message" : "messages")"
        return unread > 0 ? "\(total), \(unread) unread" : total
    }

    private var demoBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
            Text("You're looking at sample mail.")
            Spacer()
            Button("Connect Gmail") { store.leaveDemo() }
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.yellow.opacity(0.16))
    }
}
