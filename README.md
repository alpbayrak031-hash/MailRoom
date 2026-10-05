# Mailroom

A native macOS app that signs in to your Gmail accounts and sorts incoming mail into groups you define
(for example "Google Classroom" or "everyone @uaa.k12.tr").

## Build and run

Requires macOS 26 and the Swift toolchain (Command Line Tools are enough; Xcode is not needed).

```bash
./build.sh
```

```bash
open dist/Mailroom.app
```

## Connecting Gmail

Google only lets an app read mail through an OAuth client, and each person creates their own. Once:

1. Create a project at <https://console.cloud.google.com/projectcreate>.
2. Enable the Gmail API: <https://console.cloud.google.com/apis/library/gmail.googleapis.com>.
3. In **Google Auth Platform → Audience**, choose **External** and add every Gmail address you'll sign in
   with under **Test users**.
4. In **Google Auth Platform → Clients**, create a client of type **Desktop app**.
5. Paste its client ID and client secret into Mailroom and click **Sign in with Google**.

Add more accounts from **Settings (⌘,) → Add Account**.

Notes:

- While the Google project is in "Testing", Google expires sign-ins after 7 days. Mailroom shows a warning
  next to the account; right-click it and choose **Sign In Again**. Publishing the project
  (Audience → Publish app) removes the limit.
- School accounts only work if the school's Google Workspace admin allows third-party apps.

## How it works

- Access is read-only (`gmail.readonly`). Mailroom never changes, sends or deletes mail.
- Opening a message marks it read in Mailroom only; it can still show as unread in Gmail.
  Right-click a message to mark it read or unread again.
- It shows the newest 300 inbox messages per account and refreshes every five minutes (⌘R to refresh now).
- Groups are rules on sender, sender domain, subject or recipient. A message can be in several groups.
- Sign-in tokens are stored in the macOS keychain. Groups, read marks and a cache of message headers
  live in `~/Library/Application Support/Mailroom`.

## Layout

- `Sources/Mailroom/GoogleOAuth.swift` — sign-in (authorization code + PKCE over a loopback redirect)
- `Sources/Mailroom/GmailClient.swift` — Gmail REST calls and header/body parsing
- `Sources/Mailroom/AppStore.swift` — app state, syncing, persistence
- `Sources/Mailroom/Views/` — SwiftUI interface
- `Support/` — Info.plist, app icon and the script that draws it
