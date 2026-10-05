import SwiftUI

struct GroupEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var group: MailGroup
    private let isNew: Bool
    @FocusState private var nameFocused: Bool
    @State private var confirmsDelete = false

    init(draft: GroupDraft) {
        _group = State(initialValue: draft.group)
        isNew = draft.isNew
    }

    private var matches: [MailMessage] { store.messages.filter { group.matches($0) } }
    private var canSave: Bool { group.rules.contains(where: \.isComplete) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    identity
                    appearance
                    rules
                    preview
                }
                .padding(24)
            }
            Divider()
            footer
        }
        .frame(width: 600, height: 560)
        .onAppear { nameFocused = isNew && group.name.isEmpty }
    }

    private var identity: some View {
        HStack(spacing: 14) {
            GroupBadge(symbol: group.symbol, color: group.color.color, size: 52)
            TextField("Group name", text: $group.name)
                .textFieldStyle(.plain)
                .font(.title.weight(.semibold))
                .focused($nameFocused)
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                ForEach(GroupColor.allCases) { option in
                    Button { group.color = option } label: {
                        Circle()
                            .fill(option.color.gradient)
                            .frame(width: 24, height: 24)
                            .overlay {
                                if group.color == option {
                                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.rawValue.capitalized)
                    .accessibilityAddTraits(group.color == option ? .isSelected : [])
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 8), count: 12), alignment: .leading, spacing: 8) {
                ForEach(MailGroup.symbols, id: \.self) { symbol in
                    let selected = group.symbol == symbol
                    Button { group.symbol = symbol } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(selected ? .white : .secondary)
                            .frame(width: 36, height: 36)
                            .background(
                                selected ? AnyShapeStyle(group.color.color.gradient) : AnyShapeStyle(Color.primary.opacity(0.06)),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(symbol)
                }
            }
        }
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Include mail that matches")
                Picker("Match", selection: $group.mode) {
                    Text("any").tag(MailGroup.Mode.any)
                    Text("all").tag(MailGroup.Mode.all)
                }
                .labelsHidden()
                .fixedSize()
                Text("of these rules:")
            }
            .font(.headline)

            ForEach($group.rules) { $rule in
                HStack(spacing: 8) {
                    Picker("Field", selection: $rule.field) {
                        ForEach(MailRule.Field.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                    Picker("Condition", selection: $rule.op) {
                        ForEach(MailRule.Op.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 112)
                    TextField(rule.field.placeholder, text: $rule.value)
                        .textFieldStyle(.roundedBorder)
                    Button("Remove Rule", systemImage: "minus.circle.fill") {
                        group.rules.removeAll { $0.id == rule.id }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(group.rules.count == 1)
                }
            }
            Button("Add Rule", systemImage: "plus") { group.rules.append(MailRule()) }
                .buttonStyle(.borderless)
        }
    }

    private var preview: some View {
        let matches = matches
        return Card(tint: group.color.color, cornerRadius: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text(
                    canSave
                        ? "Matches \(matches.count) of \(store.messages.count) messages in your inbox"
                        : "Fill in a rule to see what it matches"
                )
                .font(.callout.weight(.semibold))
                ForEach(matches.prefix(4)) { message in
                    HStack(spacing: 8) {
                        Text(message.senderDisplay).lineLimit(1).layoutPriority(1)
                        Text(message.subject).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .font(.callout)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack {
            if !isNew {
                Button("Delete Group…", role: .destructive) { confirmsDelete = true }
                    .confirmationDialog("Delete “\(group.name)”?", isPresented: $confirmsDelete) {
                        Button("Delete Group", role: .destructive) {
                            store.delete(group)
                            dismiss()
                        }
                    } message: {
                        Text("Only the group and its rules are removed. Your mail stays where it is.")
                    }
            }
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(isNew ? "Create Group" : "Save") {
                store.commit(group)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        }
        .padding(16)
    }
}
