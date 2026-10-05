import SwiftUI

struct WelcomeView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content.frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
        .background { WelcomeBackdrop().ignoresSafeArea() }
    }

    private var content: some View {
        VStack(spacing: 26) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 104, height: 104)
                    .accessibilityHidden(true)
                Text("Welcome to Mailroom").font(.system(size: 38, weight: .bold))
                Text("All your Gmail inboxes, sorted into groups you define.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Card(cornerRadius: 22) {
                VStack(alignment: .leading, spacing: 18) {
                    GoogleClientFields()
                    SignInControls()
                }
                .padding(22)
            }
            .frame(maxWidth: 560)

            Button("Explore with sample data") { store.enterDemo() }
                .buttonStyle(.link)
        }
        .padding(40)
    }
}

private struct WelcomeBackdrop: View {
    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.55, 0.45], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [
                .indigo, .blue, .teal,
                .purple, .indigo, .mint,
                .pink, .orange, .yellow,
            ]
        )
        .opacity(0.16)
    }
}

/// Client ID and secret entry plus the one-time Google Cloud walkthrough.
struct GoogleClientFields: View {
    @Environment(AppStore.self) private var store
    @State private var showsSteps = false

    private static let steps: [(String, URL?)] = [
        ("Create a project in Google Cloud Console.", URL(string: "https://console.cloud.google.com/projectcreate")),
        ("Enable the Gmail API for that project.", URL(string: "https://console.cloud.google.com/apis/library/gmail.googleapis.com")),
        ("Under Google Auth Platform → Audience, choose External and add each Gmail address you'll sign in with as a test user.",
         URL(string: "https://console.cloud.google.com/auth/audience")),
        ("Under Clients, create a client of type “Desktop app”.", URL(string: "https://console.cloud.google.com/auth/clients")),
        ("Paste its client ID and client secret below.", nil),
    ]

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Connect to Google").font(.title3.weight(.semibold))
                Text("Mailroom signs in with your own Google OAuth client, so your mail only ever travels between this Mac and Google. Access is read-only.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DisclosureGroup("How to get a client ID (about 5 minutes, once)", isExpanded: $showsSteps) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .monospacedDigit()
                                .frame(width: 20, height: 20)
                                .background(Color.accentColor.opacity(0.18), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.0).fixedSize(horizontal: false, vertical: true)
                                if let url = step.1 {
                                    Link("Open in browser", destination: url).font(.callout)
                                }
                            }
                        }
                    }
                    Text("School accounts only work if the school's Google Workspace admin allows third-party apps.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 10)
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("Client ID", text: $store.config.clientID, prompt: Text("1234567890-abc….apps.googleusercontent.com"))
                SecureField("Client secret", text: $store.config.clientSecret, prompt: Text("Client secret"))
                if store.config.isUsable, !store.config.looksValid {
                    Label("Client IDs end in .apps.googleusercontent.com", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
        }
    }
}

struct SignInControls: View {
    @Environment(AppStore.self) private var store
    var title = "Sign in with Google"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    store.signIn()
                } label: {
                    Label(title, systemImage: "person.crop.circle.badge.plus").padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!store.config.isUsable || store.isSigningIn)

                if store.isSigningIn {
                    ProgressView().controlSize(.small)
                    Text("Finish signing in in your browser…").foregroundStyle(.secondary)
                    Button("Cancel") { store.cancelSignIn() }
                }
            }
            if let error = store.signInError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
