import SwiftUI

/// A speaker that throbs like it follows the sound; still when Reduce Motion is on.
struct AudioBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.metrics) private var metrics
    let help: String

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let level = reduceMotion ? 0.7 : AudioPulse.level(at: context.date.timeIntervalSinceReferenceDate)
            Text("🔊")
                .font(metrics.typography.rowTitle)
                .scaleEffect(0.82 + 0.36 * level)
                .opacity(0.6 + 0.4 * level)
        }
        .tooltip(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(help)
    }
}
