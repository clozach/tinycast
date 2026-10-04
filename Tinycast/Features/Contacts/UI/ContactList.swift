import SwiftUI

/// The list both contact screens draw: an optional heading, then one row per card or field.
struct ContactList: View {
    struct Item: Identifiable, Equatable {
        let id: String
        let symbol: String
        let title: String
        let detail: String?
        let trailing: String?
    }

    @Environment(\.metrics) private var metrics
    let title: String?
    let items: [Item]
    let selectedID: String?
    let scroll: ScrollIntent
    let onActivate: (Int) -> Void
    let onActions: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let title { SectionHeader(title: title, isFirst: true) }
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ContactRow(item: item, selected: item.id == selectedID)
                            .contentShape(Rectangle())
                            .onTapGesture { onActivate(index) }
                            .onRightClick { onActions(index) }
                            .selectionFrame(item.id == selectedID)
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selectedID, atOrigin: selectedID != nil && selectedID == items.first?.id,
                proxy: proxy)
        }
    }
}

private struct ContactRow: View {
    @Environment(\.metrics) private var metrics
    let item: ContactList.Item
    let selected: Bool
    @State private var hovered = false

    /// Selection wins over hover when a row is both; otherwise hover shows its fainter layer.
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            Image(systemName: item.symbol)
                .font(.system(size: metrics.size.resultRowIcon * 0.62))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            Text(item.title)
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
                .help(item.title)
            if let detail = item.detail {
                Text(detail)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let trailing = item.trailing {
                Text(trailing)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
    }
}
