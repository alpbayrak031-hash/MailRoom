import Foundation

/// Fictional inbox used by "Explore with sample data" on the welcome screen.
enum SampleData {
    static let personal = "you@gmail.com"
    static let school = "student@my.uaa.k12.tr"
    static let accounts = [Account(email: personal), Account(email: school)]

    private struct Seed {
        var hoursAgo: Double
        var account: String
        var name: String
        var address: String
        var subject: String
        var snippet: String
        var unread = false
    }

    private static let seeds: [Seed] = [
        Seed(hoursAgo: 0.4, account: school, name: "Elif Demir (Classroom)", address: "no-reply@classroom.google.com",
             subject: "New assignment: Lab report — Projectile motion",
             snippet: "Elif Demir posted a new assignment in Physics 11-B. Due Friday at 23:59.", unread: true),
        Seed(hoursAgo: 1.2, account: school, name: "Mert Kaya", address: "mert.kaya@my.uaa.k12.tr",
             subject: "Robotics club meeting moved to Thursday",
             snippet: "Hi everyone, the workshop is booked on Wednesday so we'll meet Thursday after 8th period instead.", unread: true),
        Seed(hoursAgo: 2.5, account: personal, name: "GitHub", address: "notifications@github.com",
             subject: "[email-visualizer] Run failed: build — main",
             snippet: "The workflow run for commit 4f2a9c1 failed in 38 seconds. View the logs to see what went wrong.", unread: true),
        Seed(hoursAgo: 3.1, account: school, name: "Zeynep Arslan (Classroom)", address: "no-reply@classroom.google.com",
             subject: "Due tomorrow: Essay draft — The Great Gatsby",
             snippet: "Your work for English Literature is due tomorrow. You haven't turned it in yet."),
        Seed(hoursAgo: 5, account: personal, name: "Deniz", address: "deniz.yildiz@gmail.com",
             subject: "Saturday?",
             snippet: "Are we still on for the match on Saturday? I can bring the ball if you sort out the pitch.", unread: true),
        Seed(hoursAgo: 7.5, account: school, name: "UAA Front Office", address: "office@uaa.k12.tr",
             subject: "Parent–teacher conferences: sign-up is open",
             snippet: "Conference slots for the first term are now open. Please share the link below with your parents."),
        Seed(hoursAgo: 9, account: personal, name: "Notion", address: "team@mail.notion.so",
             subject: "What's new: faster databases and offline pages",
             snippet: "This month we rebuilt database loading from the ground up. Here's everything that shipped."),
        Seed(hoursAgo: 20, account: school, name: "Elif Demir (Classroom)", address: "no-reply@classroom.google.com",
             subject: "Returned: Quiz 3 — Kinematics",
             snippet: "Elif Demir returned your work with a grade of 92/100 and left a private comment."),
        Seed(hoursAgo: 23, account: personal, name: "GitHub", address: "notifications@github.com",
             subject: "[email-visualizer] Pull request #12 merged",
             snippet: "Merged #12 into main. 3 commits, 214 additions and 67 deletions across 9 files."),
        Seed(hoursAgo: 26, account: personal, name: "Steam", address: "noreply@steampowered.com",
             subject: "An item on your wishlist is on sale",
             snippet: "Hollow Knight: Silksong is now 20% off. This offer ends Monday at 20:00."),
        Seed(hoursAgo: 30, account: school, name: "Ayşe Çelik", address: "ayse.celik@uaa.k12.tr",
             subject: "Math Olympiad practice set 4",
             snippet: "Attached is this week's practice set. Problems 6 and 9 are the ones we'll go through on Monday.", unread: true),
        Seed(hoursAgo: 33, account: personal, name: "Duolingo", address: "hello@duolingo.com",
             subject: "Your 42-day streak is waiting",
             snippet: "Five minutes of German keeps the streak alive. Pick up where you left off."),
        Seed(hoursAgo: 49, account: school, name: "Burak Şahin (Classroom)", address: "no-reply@classroom.google.com",
             subject: "New material: Chapter 5 slides — Chemical bonding",
             snippet: "Burak Şahin posted new material in Chemistry 11-B."),
        Seed(hoursAgo: 52, account: personal, name: "Trendyol", address: "siparis@trendyol.com",
             subject: "Your order is on its way",
             snippet: "Good news — your package left the warehouse and should arrive within two working days."),
        Seed(hoursAgo: 55, account: personal, name: "GitHub", address: "notifications@github.com",
             subject: "[swift-collections] New release 1.3.0",
             snippet: "A new release is available. This version adds a tree-based sorted collection and fixes two crashes."),
        Seed(hoursAgo: 74, account: school, name: "Mert Kaya", address: "mert.kaya@my.uaa.k12.tr",
             subject: "Re: Regional qualifier — parts list",
             snippet: "Looks good. Add two spare motor controllers to the order, we burned one out last season."),
        Seed(hoursAgo: 78, account: personal, name: "Notion", address: "team@mail.notion.so",
             subject: "Deniz invited you to “Trip planning”",
             snippet: "You've been invited to edit a page. Open it to start collaborating."),
        Seed(hoursAgo: 98, account: school, name: "Zeynep Arslan (Classroom)", address: "no-reply@classroom.google.com",
             subject: "New announcement in English Literature",
             snippet: "Reminder that the library visit is on Tuesday. Bring your reading journals."),
        Seed(hoursAgo: 120, account: personal, name: "Steam", address: "noreply@steampowered.com",
             subject: "Thank you for your purchase",
             snippet: "Your receipt for the Autumn bundle is attached. The game is now available in your library."),
        Seed(hoursAgo: 127, account: school, name: "UAA Front Office", address: "office@uaa.k12.tr",
             subject: "Schedule change for Republic Day week",
             snippet: "Classes end at 13:00 on the 28th and the campus is closed on the 29th."),
        Seed(hoursAgo: 150, account: personal, name: "Duolingo", address: "hello@duolingo.com",
             subject: "You moved up to the Sapphire League",
             snippet: "You finished third this week. Keep it up to stay in the promotion zone."),
        Seed(hoursAgo: 190, account: personal, name: "Deniz", address: "deniz.yildiz@gmail.com",
             subject: "Photos from the weekend",
             snippet: "Finally uploaded them. The one of you falling into the lake is the best thing I've ever taken."),
        Seed(hoursAgo: 240, account: school, name: "Burak Şahin (Classroom)", address: "no-reply@classroom.google.com",
             subject: "Returned: Lab safety worksheet",
             snippet: "Burak Şahin returned your work with a grade of 100/100."),
        Seed(hoursAgo: 300, account: personal, name: "Trendyol", address: "siparis@trendyol.com",
             subject: "How was your order?",
             snippet: "Rate the items you received and help other shoppers decide."),
        Seed(hoursAgo: 410, account: school, name: "Ayşe Çelik", address: "ayse.celik@uaa.k12.tr",
             subject: "Olympiad team selection results",
             snippet: "Congratulations — you've been selected for the school team. First session is next Wednesday."),
        Seed(hoursAgo: 520, account: personal, name: "Apple", address: "no_reply@email.apple.com",
             subject: "Your receipt from Apple",
             snippet: "iCloud+ with 50 GB of storage. Billed monthly to the payment method on file."),
    ]

    static func messages(now: Date = Date()) -> [MailMessage] {
        seeds.enumerated().map { index, seed in
            MailMessage(
                id: "\(seed.account)/sample-\(index)",
                gmailID: "sample-\(index)",
                threadID: "sample-\(index)",
                account: seed.account,
                fromName: seed.name,
                fromAddress: seed.address,
                to: seed.account,
                subject: seed.subject,
                snippet: seed.snippet,
                date: now.addingTimeInterval(-seed.hoursAgo * 3600),
                isUnread: seed.unread
            )
        }
    }

    static func body(for message: MailMessage) -> MailBody {
        let note = "This is sample mail. Connect a Gmail account to see your own."
        // Newsletters get a rich body so both rendering paths can be previewed.
        guard message.fromAddress.hasSuffix("notion.so") else {
            return MailBody(text: "\(message.snippet)\n\n— \(message.senderDisplay)\n\n(\(note))")
        }
        return MailBody(html: """
        <div style="max-width:560px;margin:24px auto;font:16px/1.6 -apple-system,sans-serif;color:#1f2328">
          <h1 style="font-size:26px;margin:0 0 12px">\(MailParsing.escapeHTML(message.subject))</h1>
          <p>\(MailParsing.escapeHTML(message.snippet))</p>
          <p><a href="https://example.com" style="display:inline-block;padding:10px 18px;border-radius:8px;background:#1f2328;color:#fff;text-decoration:none">Read more</a></p>
          <p style="color:#6e7781;font-size:13px">\(note)</p>
        </div>
        """)
    }
}
