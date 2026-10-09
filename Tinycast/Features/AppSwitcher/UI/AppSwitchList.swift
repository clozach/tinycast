import SwiftUI

struct AppSwitchList: View {
    @Environment(\.metrics) private var metrics
    let entries: [AppSwitchEntry]
    let selection: Int
    let scroll: ScrollIntent
    let onActivate: (Int) -> Void

    private var selectedID: String? {
        entries.indices.contains(selection) ? String(entries[selection].id) : nil
    }

    var body: some View {
        if entries.isEmpty {
            EmptyResults(text: "No open apps found")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            Button { onActivate(index) } label: {
                                AppSwitchRow(entry: entry, selected: String(entry.id) == selectedID)
                            }
                            .buttonStyle(.plain)
                            .selectionFrame(String(entry.id) == selectedID)
                            .id(String(entry.id))
                        }
                    }
                    .padding(.horizontal, metrics.spacing.md)
                    .padding(.vertical, metrics.spacing.md)
                    .hideNativeScrollers()
                    .scrollOriginAnchor()
                }
                .edgeDissolve()
                .thinScrollbar()
                .scrollFollowsSelection(
                    scroll, row: selectedID, atOrigin: selection == 0, proxy: proxy)
            }
        }
    }
}

private struct AppSwitchRow: View {
    @Environment(\.metrics) private var metrics
    let entry: AppSwitchEntry
    let selected: Bool
    @State private var hovered = false

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            if let path = entry.bundlePath {
                EntryIconView(source: .file(stamp: 0), fileURL: URL(fileURLWithPath: path))
                    .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            }
            Text(entry.name)
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
                .tooltip(entry.name)
            Spacer(minLength: metrics.spacing.md)
            if selected {
                Text("Windows →")
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: metrics.radius.row)
            .fill(selected ? Theme.Colors.selection : hovered ? Theme.Colors.rowHover : .clear))
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
