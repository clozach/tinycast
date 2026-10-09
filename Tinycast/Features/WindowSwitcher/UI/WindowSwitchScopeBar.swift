import SwiftUI

struct WindowSwitchScopeBar: View {
    @Environment(\.metrics) private var metrics
    let name: String
    let includesHidden: Bool

    var body: some View {
        HStack {
            Text(name).lineLimit(1).tooltip(name)
            Spacer()
            Text(includesHidden ? "Hidden included · ⌥ held" : "Hold ⌥ for hidden")
        }
        .font(metrics.typography.rowTrailing)
        .foregroundStyle(.secondary)
        .padding(.horizontal, metrics.spacing.lg)
        .padding(.top, metrics.spacing.sm)
    }
}
