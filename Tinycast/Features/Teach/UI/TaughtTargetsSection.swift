import SwiftUI

struct TaughtTargetsSection: View {
    let coordinator: TeachCoordinator
    let store: TeachStore

    var body: some View {
        Section("Taught Targets") {
            if let error = store.loadError {
                Text(error).foregroundStyle(.orange)
            }
            ForEach(store.targets) { target in
                HStack {
                    VStack(alignment: .leading) {
                        Text(target.displayTitle)
                        Text(target.targetPreview)
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("Edit…") { coordinator.edit(target) }
                }
            }
            Button("Teach Tinycast…") { coordinator.request() }
            Button("Undo Last Teaching") { coordinator.undo() }
                .disabled(!coordinator.canUndo)
        }
    }
}
