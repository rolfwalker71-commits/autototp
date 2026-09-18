import AutototpCore
import SwiftUI

// MARK: - Confirm (single match)

struct ConfirmFillView: View {
    let item: AccountItem
    let matchLabel: String
    let targetTitle: String
    let sendEnter: Bool
    var frozenDate: Date?
    var onConfirm: () -> Void = {}
    var onChooseOther: () -> Void = {}
    var onCancel: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                LogoTile(name: item.name, image: item.logo, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(item.login.isEmpty ? (item.issuer.isEmpty ? "Kein Aussteller" : item.issuer) : item.login)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(matchLabel)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.tint.opacity(0.15), in: Capsule())
                    .foregroundStyle(.tint)
                    .lineLimit(1)
            }

            TimelineView(.animation(minimumInterval: 0.1, paused: frozenDate != nil)) { context in
                let now = frozenDate ?? context.date
                HStack {
                    CodeText(code: item.code(at: now), expiring: TOTP.remainingSeconds(period: item.model.period, date: now) <= 10, size: 30)
                    Spacer()
                    CountdownRing(period: item.model.period, date: now, size: 30)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Label {
                Text(targetTitle.isEmpty ? "Ins aktive Fenster einfügen" : "Einfügen in „\(targetTitle)“")
                    .lineLimit(2)
            } icon: {
                Image(systemName: "macwindow")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            HStack {
                Button("Anderer Account …", action: onChooseOther)
                Spacer()
                Button("Abbrechen", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(sendEnter ? "Einfügen + ↩" : "Einfügen", action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 380)
    }
}

// MARK: - Quick picker (Spotlight-style)

struct QuickPickerView: View {
    let items: [AccountItem]
    let preferredIDs: Set<UUID>
    let targetTitle: String
    var frozenDate: Date?
    var initialQuery = ""
    var onPick: (AccountItem) -> Void = { _ in }
    var onCopy: (AccountItem) -> Void = { _ in }
    var onCancel: () -> Void = {}

    @State private var query = ""
    @State private var selectedID: UUID?
    @FocusState private var searchFocused: Bool

    private var sections: [(title: String, items: [AccountItem])] {
        let visible = items.filter { $0.matches(filter: query) }
        let preferred = visible.filter { preferredIDs.contains($0.id) }
        let others = visible.filter { !preferredIDs.contains($0.id) }
        if preferred.isEmpty {
            return [("", others)]
        }
        return [("Passend zum Fenster", preferred), ("Alle Accounts", others)].filter { !$0.items.isEmpty }
    }

    private var flat: [AccountItem] {
        sections.flatMap(\.items)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Account suchen", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
                    .focused($searchFocused)
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.return) { pickSelected(); return .handled }
                    .onKeyPress(.escape) { onCancel(); return .handled }
                    .onKeyPress(characters: ["c"], phases: .down) { press in
                        guard press.modifiers.contains(.command), let item = selectedItem else {
                            return .ignored
                        }
                        onCopy(item)
                        return .handled
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            TimelineView(.animation(minimumInterval: 0.1, paused: frozenDate != nil)) { context in
                let now = frozenDate ?? context.date
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(sections, id: \.title) { section in
                                if !section.title.isEmpty {
                                    Text(section.title)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 10)
                                        .padding(.top, 8)
                                        .padding(.bottom, 2)
                                }
                                ForEach(section.items) { item in
                                    PickerRow(item: item, date: now, selected: item.id == selectedID)
                                        .id(item.id)
                                        .onTapGesture(count: 2) { onPick(item) }
                                        .onTapGesture { selectedID = item.id }
                                }
                            }
                            if flat.isEmpty {
                                Text("Kein Account gefunden")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 24)
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: selectedID) { _, id in
                        if let id {
                            proxy.scrollTo(id)
                        }
                    }
                }
            }
            .frame(height: min(CGFloat(max(flat.count, 1)) * 52 + (sections.count > 1 ? 56 : 12), 330))

            Divider()

            HStack(spacing: 14) {
                if !targetTitle.isEmpty {
                    Label(targetTitle, systemImage: "macwindow")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                hint("↩", "Einfügen")
                hint("⌘C", "Kopieren")
                hint("esc", "Schliessen")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 500)
        .onAppear {
            query = initialQuery
            selectedID = flat.first?.id
            searchFocused = true
        }
        .onChange(of: query) {
            selectedID = flat.first?.id
        }
    }

    private var selectedItem: AccountItem? {
        flat.first { $0.id == selectedID }
    }

    private func hint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            KeyCap(text: key)
            Text(text)
        }
    }

    private func move(_ delta: Int) {
        let list = flat
        guard !list.isEmpty else {
            return
        }
        let index = list.firstIndex { $0.id == selectedID } ?? -1
        selectedID = list[min(max(index + delta, 0), list.count - 1)].id
    }

    private func pickSelected() {
        if let item = selectedItem {
            onPick(item)
        }
    }
}

private struct PickerRow: View {
    let item: AccountItem
    let date: Date
    let selected: Bool

    var body: some View {
        let seconds = TOTP.remainingSeconds(period: item.model.period, date: date)
        HStack(spacing: 10) {
            LogoTile(name: item.name, image: item.logo, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(item.login.isEmpty ? item.detail : item.login)
                    .font(.system(size: 11))
                    .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            Spacer()
            Text(item.code(at: date).map(TOTP.format) ?? "––– –––")
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(selected ? AnyShapeStyle(.white) : seconds <= 10 ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
            Text("\(seconds)s")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                .frame(width: 26, alignment: .trailing)
        }
        .foregroundStyle(selected ? .white : .primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.tint)
            }
        }
        .contentShape(Rectangle())
    }
}
