import SwiftUI

struct OverviewView: View {
    @Environment(AppStore.self) private var store

    private let columns = [GridItem(.adaptive(minimum: 290, maximum: 460), spacing: 16, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header
                stats
                if !store.messages.isEmpty { BreakdownBar() }
                groupsSection
                if !store.suggestions.isEmpty { suggestionsSection }
            }
            .padding(28)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting).font(.largeTitle.weight(.bold))
            Text(summary).font(.title3).foregroundStyle(.secondary)
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    private var summary: String {
        if store.messages.isEmpty { return store.isSyncing ? "Loading your mail…" : "Your inbox is empty." }
        let unread = store.unreadTotal
        return unread == 0
            ? "You're all caught up."
            : "\(unread) unread \(unread == 1 ? "message" : "messages") across \(store.accounts.count) \(store.accounts.count == 1 ? "account" : "accounts")."
    }

    private var stats: some View {
        let grouped = store.messages.count - store.messages(in: .ungrouped).count
        return HStack(spacing: 16) {
            StatTile(title: "In Inbox", value: store.messages.count, symbol: "tray.full.fill", item: .inbox)
            StatTile(title: "Unread", value: store.unreadTotal, symbol: "envelope.badge.fill", item: .inbox)
            StatTile(title: "Sorted into Groups", value: grouped, symbol: "square.stack.3d.up.fill", item: nil)
            StatTile(title: "Everything Else", value: store.messages.count - grouped, symbol: "tray.fill", item: .ungrouped)
        }
    }

    private var groupsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Groups").font(.title2.weight(.semibold))
                Spacer()
                Button("New Group", systemImage: "plus") { store.beginNewGroup() }
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(store.groups) { GroupCard(group: $0) }
            }
            if store.groups.isEmpty {
                Text("Groups collect mail by sender, domain, subject or recipient. Create one to get started.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Suggested Groups").font(.title2.weight(.semibold))
                Text("Senders that keep showing up in Everything Else.").foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(store.suggestions) { suggestion in
                    Card(cornerRadius: 14) {
                        HStack(spacing: 12) {
                            AvatarView(name: suggestion.title, seed: suggestion.title, size: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(suggestion.title).font(.headline).lineLimit(1).truncationMode(.middle)
                                Text("\(suggestion.count) messages").font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Button("Group") { store.beginNewGroup(name: suggestion.title, rule: suggestion.rule) }
                        }
                        .padding(12)
                    }
                }
            }
        }
    }
}

private struct StatTile: View {
    @Environment(AppStore.self) private var store
    let title: String
    let value: Int
    let symbol: String
    let item: SidebarItem?

    var body: some View {
        if let item {
            Button { store.selection = item } label: { tile }
                .buttonStyle(.plain)
        } else {
            tile
        }
    }

    private var tile: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: symbol)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(value, format: .number)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// How the inbox splits across groups. A message in several groups counts
/// toward the first one in sidebar order, so segments add up to the inbox.
private struct BreakdownBar: View {
    @Environment(AppStore.self) private var store

    private struct Segment: Identifiable {
        var id: String
        var name: String
        var color: Color
        var count: Int
        var item: SidebarItem
    }

    private var segments: [Segment] {
        var counts: [UUID: Int] = [:]
        var rest = 0
        for message in store.messages {
            if let first = store.membership[message.id]?.first { counts[first, default: 0] += 1 } else { rest += 1 }
        }
        var result = store.groups.compactMap { group -> Segment? in
            guard let count = counts[group.id] else { return nil }
            return Segment(id: group.id.uuidString, name: group.name, color: group.color.color, count: count, item: .group(group.id))
        }
        if rest > 0 {
            result.append(Segment(id: "rest", name: "Everything Else", color: Color.primary.opacity(0.22), count: rest, item: .ungrouped))
        }
        return result
    }

    var body: some View {
        let segments = segments
        let total = max(1, segments.reduce(0) { $0 + $1.count })
        VStack(alignment: .leading, spacing: 12) {
            Text("Inbox Breakdown").font(.title2.weight(.semibold))
            GeometryReader { proxy in
                let gap: CGFloat = 2
                let available = proxy.size.width - gap * CGFloat(max(0, segments.count - 1))
                HStack(spacing: gap) {
                    ForEach(segments) { segment in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(segment.color)
                            .frame(width: max(4, available * CGFloat(segment.count) / CGFloat(total)))
                            .help("\(segment.name): \(segment.count) of \(total)")
                    }
                }
            }
            .frame(height: 14)
            .accessibilityHidden(true)

            FlowLayout(spacing: 18, lineSpacing: 8) {
                ForEach(segments) { segment in
                    Button { store.selection = segment.item } label: {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(segment.color).frame(width: 10, height: 10)
                            Text(segment.name)
                            Text("\(segment.count) · \(segment.count * 100 / total)%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.callout)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct GroupCard: View {
    @Environment(AppStore.self) private var store
    let group: MailGroup
    @State private var isHovered = false

    var body: some View {
        let messages = store.messages(in: .group(group.id))
        let unread = messages.count { $0.isUnread }
        Button { store.selection = .group(group.id) } label: {
            Card(tint: group.color.color) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        GroupBadge(symbol: group.symbol, color: group.color.color, size: 40)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(group.name).font(.title3.weight(.semibold)).lineLimit(1)
                            Text(summary(count: messages.count, unread: unread))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        // Room for the options menu laid over the card.
                        Color.clear.frame(width: 24, height: 1)
                    }
                    .padding(16)

                    Divider().opacity(0.6)

                    VStack(alignment: .leading, spacing: 11) {
                        if messages.isEmpty {
                            Text("No matching mail yet.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                        }
                        ForEach(messages.prefix(3)) { message in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Circle()
                                    .fill(message.isUnread ? group.color.color : .clear)
                                    .frame(width: 6, height: 6)
                                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 3 }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(message.subject)
                                        .font(.callout.weight(message.isUnread ? .semibold : .regular))
                                        .lineLimit(1)
                                    Text(message.senderDisplay).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Text(MailDate.short(message.date))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .shadow(color: .black.opacity(isHovered ? 0.12 : 0), radius: 14, y: 6)
            .scaleEffect(isHovered ? 1.012 : 1)
            .animation(.snappy(duration: 0.18), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .overlay(alignment: .topTrailing) {
            Menu {
                actions
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Edit or delete this group")
            .accessibilityLabel("Options for \(group.name)")
            .padding(.top, 25)
            .padding(.trailing, 14)
        }
        .contextMenu { actions }
    }

    private func summary(count: Int, unread: Int) -> String {
        let total = "\(count) \(count == 1 ? "message" : "messages")"
        return unread > 0 ? "\(total) · \(unread) unread" : total
    }

    @ViewBuilder
    private var actions: some View {
        Button("Edit Group…", systemImage: "pencil") { store.beginEditing(group) }
        Divider()
        Button("Delete Group…", systemImage: "trash", role: .destructive) { store.groupToDelete = group }
    }
}

/// Left-aligned wrapping row, used for the breakdown legend.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, origin) in arrange(subviews, width: bounds.width).origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified
            )
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (origins: [CGPoint], width: CGFloat, height: CGFloat) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxWidth = max(maxWidth, x - spacing)
        }
        return (origins, maxWidth, y + rowHeight)
    }
}
