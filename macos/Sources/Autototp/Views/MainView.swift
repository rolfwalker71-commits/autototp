import AutototpCore
import SwiftUI

enum MainSheet: Identifiable {
    case add
    case edit(UUID)
    case importAccounts

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let id): return "edit-\(id)"
        case .importAccounts: return "import"
        }
    }
}

struct MainView: View {
    @ObservedObject var model: AppModel
    var openSettings: () -> Void = {}
    /// Fixed clock for screenshots; nil means live.
    var frozenDate: Date?

    @State private var search = ""
    @State private var selection: UUID?
    @State private var copiedID: UUID?
    @State private var pendingDelete: AccountItem?

    init(model: AppModel, openSettings: @escaping () -> Void = {}, frozenDate: Date? = nil) {
        self.model = model
        self.openSettings = openSettings
        self.frozenDate = frozenDate
    }

    private var filtered: [AccountItem] {
        model.items.filter { $0.matches(filter: search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !model.accessibilityTrusted {
                AccessibilityBanner()
            }

            if model.items.isEmpty {
                EmptyStateView(add: { model.sheet = .add }, importAccounts: { model.sheet = .importAccounts })
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                accountList
            }

            footer
        }
        .background(BackgroundWash(animated: model.settings.animatedBackground))
        .frame(minWidth: 440, idealWidth: 480, minHeight: 360, idealHeight: 560)
        .navigationTitle("Autototp")
        .searchable(text: $search, placement: .toolbar, prompt: "Name, Aussteller oder Match")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.sheet = .importAccounts
                } label: {
                    Label("Importieren", systemImage: "square.and.arrow.down")
                }
                .help("2FAS-Backup oder otpauth://-Links importieren")

                Button {
                    model.sheet = .add
                } label: {
                    Label("Account hinzufügen", systemImage: "plus")
                }
                .help("Account manuell hinzufügen")
            }
        }
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .add:
                AccountEditorView(model: model, existing: nil)
            case .edit(let id):
                AccountEditorView(model: model, existing: model.item(id))
            case .importAccounts:
                ImportView(model: model)
            }
        }
        .confirmationDialog(
            "„\(pendingDelete?.name ?? "")“ löschen?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                if let item = pendingDelete {
                    model.delete(item.id)
                }
                pendingDelete = nil
            }
        } message: {
            Text("Das Secret wird von diesem Mac entfernt. Stelle sicher, dass du noch einen anderen Zugang hast.")
        }
    }

    private var accountList: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: frozenDate != nil)) { context in
            let now = frozenDate ?? context.date
            List(selection: $selection) {
                ForEach(filtered) { item in
                    AccountRow(item: item, date: now, density: model.settings.density, copied: copiedID == item.id) {
                        copy(item)
                    }
                    .tag(item.id)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contextMenu(forSelectionType: UUID.self) { ids in
                if let id = ids.first, let item = model.item(id) {
                    Button("Code kopieren") { copy(item) }
                    Button("Bearbeiten …") { model.sheet = .edit(id) }
                    Divider()
                    Button("Löschen …", role: .destructive) { pendingDelete = item }
                }
            } primaryAction: { ids in
                if let id = ids.first {
                    model.sheet = .edit(id)
                }
            }
            .onCopyCommand {
                guard let id = selection, let item = model.item(id), let code = item.code() else {
                    return []
                }
                return [NSItemProvider(object: code as NSString)]
            }
            .onDeleteCommand {
                if let id = selection {
                    pendingDelete = model.item(id)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            KeyCap(text: HotkeyService.displayText)
            Text(model.hotkeyRegistered
                 ? "fügt den passenden Code ins aktive Fenster ein"
                 : "ist belegt – bitte in anderen Apps freigeben")
            Spacer()
            Text(model.items.count == 1 ? "1 Account" : "\(model.items.count) Accounts")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
    }

    private func copy(_ item: AccountItem) {
        model.copyCode(item)
        withAnimation(.easeOut(duration: 0.15)) {
            copiedID = item.id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedID == item.id {
                withAnimation { copiedID = nil }
            }
        }
    }
}

struct AccountRow: View {
    let item: AccountItem
    let date: Date
    var density: RowDensity = .comfortable
    var copied = false
    var onCopy: () -> Void = {}

    private var compact: Bool { density == .compact }

    var body: some View {
        let seconds = TOTP.remainingSeconds(period: item.model.period, date: date)
        let progress = TOTP.progress(period: item.model.period, date: date)
        HStack(spacing: compact ? 9 : 12) {
            LogoTile(name: item.name, image: item.logo, size: compact ? 26 : 36, colorIndex: item.model.colorIndex)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: compact ? 12 : 13, weight: .semibold))
                    .lineLimit(1)
                if !item.login.isEmpty {
                    Text(item.login)
                        .font(.system(size: compact ? 10.5 : 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !compact {
                    Text(item.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            ZStack(alignment: .trailing) {
                CodeText(code: item.code(at: date), expiring: seconds <= 10, size: compact ? 19 : 23)
                    .opacity(copied ? 0 : 1)
                if copied {
                    Label("Kopiert", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onCopy)
            .help("Klicken zum Kopieren")

            CountdownRing(period: item.model.period, date: date, tint: tint, size: compact ? 20 : 26)
        }
        .padding(.vertical, compact ? 5 : 9)
        .padding(.horizontal, 12)
        .overlay(alignment: .bottom) {
            ExpiryBar(progress: progress, tint: (seconds <= 10 ? .red : tint).opacity(0.55))
                .padding(.horizontal, 12)
                .padding(.bottom, 3)
        }
        .glassSurface(tint: tint, cornerRadius: compact ? 14 : 18, interactive: true)
    }

    private var tint: Color {
        item.tint
    }
}

/// Thin bar along the bottom edge of a card that empties as the code expires.
struct ExpiryBar: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.15))
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, geo.size.width * progress))
            }
        }
        .frame(height: 2.5)
    }
}

/// Soft colour wash behind the list, so the glass cards have something to refract.
/// Slowly drifting when enabled – and always still when the system asks for less motion.
private struct BackgroundWash: View {
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !animated || reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate / 26
            ZStack {
                Rectangle().fill(.background)
                blob(Theme.colors(index: 0).1, x: 0.18 + 0.12 * sin(t), y: 0.12 + 0.08 * cos(t * 0.8), opacity: 0.12)
                blob(Theme.colors(index: 2).0, x: 0.85 + 0.1 * cos(t * 0.9), y: 0.18 + 0.1 * sin(t * 1.1), opacity: 0.1)
                blob(Theme.colors(index: 4).1, x: 0.3 + 0.14 * cos(t * 0.7), y: 0.88 + 0.07 * sin(t), opacity: 0.1)
                blob(Theme.colors(index: 1).0, x: 0.8 + 0.12 * sin(t * 1.2), y: 0.8 + 0.1 * cos(t * 0.6), opacity: 0.08)
            }
            .ignoresSafeArea()
        }
    }

    private func blob(_ color: Color, x: Double, y: Double, opacity: Double) -> some View {
        RadialGradient(
            colors: [color.opacity(opacity), .clear],
            center: UnitPoint(x: x, y: y),
            startRadius: 0,
            endRadius: 260
        )
    }
}

private struct AccessibilityBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Zugriff auf „\(Permissions.accessibilityPaneName)“ fehlt")
                    .font(.system(size: 12, weight: .semibold))
                Text("Ohne ihn kann Autototp keine Fenster erkennen und keine Codes eintippen.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Erlauben …") {
                Permissions.requestAccessibility()
                Permissions.openAccessibilitySettings()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.orange.opacity(0.1))
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct EmptyStateView: View {
    let add: () -> Void
    let importAccounts: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Noch keine Accounts", systemImage: "lock.shield")
        } description: {
            Text("Importiere ein 2FAS-Backup oder füge einen Account mit seinem Secret hinzu.")
        } actions: {
            HStack {
                Button("Importieren …", action: importAccounts)
                Button("Account hinzufügen …", action: add)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxHeight: .infinity)
    }
}
