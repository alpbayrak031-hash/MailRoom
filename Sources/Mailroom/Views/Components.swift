import SwiftUI

struct AvatarView: View {
    let name: String
    let seed: String
    var size: CGFloat = 36

    private var initials: String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).prefix(2)
        let letters = words.compactMap(\.first).map(String.init).joined().uppercased()
        return letters.isEmpty ? "?" : letters
    }

    var body: some View {
        let hue = Double(seed.stableHash % 360) / 360
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(hue: hue, saturation: 0.50, brightness: 0.92),
                        Color(hue: hue, saturation: 0.72, brightness: 0.72),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct GroupBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(color.gradient)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct GroupChip: View {
    let group: MailGroup

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(group.color.color).frame(width: 6, height: 6)
            Text(group.name).font(.caption2.weight(.medium)).lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(group.color.color.opacity(0.14), in: Capsule())
    }
}

struct Card<Content: View>: View {
    var tint: Color = .clear
    var cornerRadius: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape.fill(Color.primary.opacity(0.035))
                shape.fill(LinearGradient(colors: [tint.opacity(0.16), tint.opacity(0.03)], startPoint: .top, endPoint: .bottom))
            }
            .overlay { shape.strokeBorder(Color.primary.opacity(0.07)) }
            .clipShape(shape)
            .contentShape(shape)
    }
}

enum MailDate {
    static func short(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.day().month(.abbreviated))
        }
        return date.formatted(date: .numeric, time: .omitted)
    }

    struct Bucket: Identifiable {
        var title: String
        var messages: [MailMessage]
        var id: String { title }
    }

    static func buckets(_ messages: [MailMessage], now: Date = Date()) -> [Bucket] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        func title(for date: Date) -> String {
            if date >= startOfToday { return "Today" }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: startOfToday).day ?? 0
            if days == 1 { return "Yesterday" }
            if days <= 7 { return "Previous 7 Days" }
            if days <= 30 { return "Previous 30 Days" }
            return "Older"
        }
        var result: [Bucket] = []
        for message in messages {
            let title = title(for: message.date)
            if result.last?.title == title {
                result[result.count - 1].messages.append(message)
            } else {
                result.append(Bucket(title: title, messages: [message]))
            }
        }
        return result
    }
}
