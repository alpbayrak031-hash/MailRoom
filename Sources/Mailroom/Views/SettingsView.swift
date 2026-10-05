import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Form {
            Section("Accounts") {
                if store.accounts.isEmpty {
                    Text("No accounts connected.").foregroundStyle(.secondary)
                }
                ForEach(store.accounts) { account in
                    HStack(spacing: 10) {
                        AvatarView(name: account.email, seed: account.email, size: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(account.email)
                            if let error = store.accountErrors[account.email] {
                                Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                        if !store.isDemo {
                            if store.accountErrors[account.email] != nil {
                                Button("Sign In Again") { store.signIn(loginHint: account.email) }
                            }
                            Button("Remove", role: .destructive) { store.remove(account) }
                        }
                    }
                }
                SignInControls(title: "Add Account")
            }
            Section {
                GoogleClientFields()
            }
        }
        .formStyle(.grouped)
        .frame(width: 580, height: 560)
        .onDisappear { store.saveConfig() }
    }
}
