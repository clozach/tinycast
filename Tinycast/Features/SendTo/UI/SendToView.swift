import SwiftUI

struct SendToView: View {
    @Bindable var session: SendToSession
    let cancel: () -> Void
    let send: (SendToTarget) -> Void
    @Environment(\.metrics) private var metrics
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.md) {
            HStack(spacing: metrics.spacing.md) {
                Button(action: cancel) {
                    SymbolImage(name: "chevron.left", size: metrics.size.menuIcon)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Text("Send to…").font(metrics.typography.rowTitle)
                Spacer()
                KeyCapChip(text: "esc", style: .outline)
            }
            Text("\(session.source) · \(session.payload.displayTitle)")
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(2)
            TextField("Search apps…", text: $session.query)
                .textFieldStyle(.plain)
                .font(metrics.typography.rowTitle)
                .focused($searchFocused)
                .accessibilityLabel("Search destination apps")
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: metrics.spacing.xxs) {
                        let rows = session.matches
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, target in
                            if index == 0 || target.isOpen != rows[index - 1].isOpen {
                                Text(target.isOpen ? "Open in" : "Paste into")
                                    .font(metrics.typography.sectionHeader)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, metrics.spacing.md)
                                    .padding(.bottom, metrics.spacing.xs)
                            }
                            row(target, index: index).id(target.id)
                        }
                        if rows.isEmpty {
                            Text("No matching apps")
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .padding(metrics.spacing.xl)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .onChange(of: session.selection) {
                    if let selected = session.selected { proxy.scrollTo(selected.id) }
                }
            }
            HStack {
                Text("↑↓ Choose app")
                Spacer()
                Text("↵ Send")
            }
            .font(metrics.typography.rowTrailing)
            .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(metrics.spacing.dialogInset)
        .frame(width: metrics.size.dialogWidth, height: metrics.size.panelHeight)
        .background(Theme.Colors.panelScrim)
        .background(GlassEffectView())
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius.panel, style: .continuous))
        .onAppear { searchFocused = true }
    }

    private func row(_ target: SendToTarget, index: Int) -> some View {
        Button { send(target) } label: {
            HStack(spacing: metrics.spacing.md) {
                if let url = target.appURL {
                    MenuFileIcon(path: url.path)
                } else {
                    SymbolImage(name: "app", size: metrics.size.menuIcon)
                }
                Text(target.name).font(metrics.typography.rowTitle)
                Spacer()
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, metrics.spacing.md)
            .frame(height: metrics.size.menuRowHeight)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.menuRow, style: .continuous)
                    .fill(index == session.selection ? Theme.Colors.selection : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(target.isOpen ? "Open in" : "Paste into") \(target.name)")
    }
}
