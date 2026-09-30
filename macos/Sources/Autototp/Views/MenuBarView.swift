import AutototpCore
import SwiftUI

/// Content of the menu bar panel: search, the accounts as coloured glass cards, and a footer bar.
/// A click on a card copies its code.
struct MenuBarView: View {
    @ObservedObject var model: AppModel
    var frozenDate: Date?
    var onFill: () -> Void = {}
    var onOpen: () -> Void = {}
    var onSettings: () -> Void = {}
    var onAdd: () -> Void = {}
    var onQuit: () -> Void = {}

    @State private var query = ""
    @State private var copiedID: UUID?
    @FocusState private var searchFocused: Bool

    private var filtered: [AccountItem] {
        model.items.filter { $0.matches(filter: query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)

            if model.items.isEmpty {
                empty
            } else {
                TimelineView(.animation(minimumInterval: 0.1, paused: frozenDate != nil)) { context in
                    let now = frozenDate ?? context.date
                    ScrollView {
                        LazyVStack(spacing: 5) {
                            ForEach(filtered) { item in
                                MenuAccountRow(item: item, date: now, copied: copiedID == item.id) {
                                    copy(item)
                                }
                            }
                            if filtered.isEmpty {
                                Text("Kein Account gefunden")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 28)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                    .frame(height: min(CGFloat(max(filtered.count, 1)) * 51 + 16, 392))
                }
            }

            Divider().opacity(0.4)
            footer
        }
        .frame(width: 340)
        .onAppear { searchFocused = true }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Account suchen", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searchFocused)
                .onKeyPress(.return) {
                    if let item = filtered.first { copy(item) }
                    return .handled
                }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "key.horizontal")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Noch keine Accounts")
                .font(.callout)
            Button("Account hinzufügen …", action: onAdd)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: onFill) {
                HStack(spacing: 6) {
                    Image(systemName: "text.cursor")
                    Text("Code einfügen").fixedSize()
                    KeyCap(text: HotkeyService.displayText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .glassSurface(tint: .accentColor.opacity(0.7), cornerRadius: 12, interactive: true)
            .help("Sucht den Account zum aktiven Fenster und tippt den Code ein")

            Spacer()

            iconButton("plus", "Account hinzufügen", onAdd)
            iconButton("macwindow", "Autototp öffnen", onOpen)
            iconButton("gearshape", "Einstellungen", onSettings)
            iconButton("power", "Autototp beenden", onQuit)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func iconButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 26, height: 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .glassSurface(cornerRadius: 10, interactive: true)
        .help(help)
    }

    private func copy(_ item: AccountItem) {
        model.copyCode(item)
        withAnimation(.easeOut(duration: 0.15)) { copiedID = item.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedID == item.id {
                withAnimation { copiedID = nil }
            }
        }
    }
}

private struct MenuAccountRow: View {
    let item: AccountItem
    let date: Date
    let copied: Bool
    let onCopy: () -> Void

    @State private var hovering = false

    var body: some View {
        let tint = item.tint
        let seconds = TOTP.remainingSeconds(period: item.model.period, date: date)
        Button(action: onCopy) {
            HStack(spacing: 10) {
                LogoTile(name: item.name, image: item.logo, size: 28, colorIndex: item.model.colorIndex)
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    if !item.login.isEmpty {
                        Text(item.login)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                if copied {
                    Label("Kopiert", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                        .transition(.opacity)
                } else {
                    CodeText(code: item.code(at: date), expiring: seconds <= 10, size: 19)
                    CountdownRing(period: item.model.period, date: date, tint: tint, size: 20)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassSurface(tint: hovering ? tint.opacity(0.8) : tint.opacity(0.35), cornerRadius: 14, interactive: true)
        .onHover { hovering = $0 }
        .help("Klicken kopiert den Code")
    }
}
