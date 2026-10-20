import SwiftUI

struct TeachFields: View {
    @Bindable var session: TeachSession
    let refreshApplications: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Trigger").font(.callout.weight(.medium))
            TextField("For example, dark", text: $session.trigger)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Trigger")
            Text("Target").font(.callout.weight(.medium))
            TextEditor(text: $session.target)
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
                .padding(Theme.Spacing.sm)
                .frame(height: 88)
                .background(Theme.Colors.cardFill, in: RoundedRectangle(cornerRadius: 6))
                .disabled(!session.isPayload)
                .accessibilityLabel("Target")
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if session.isPayload {
                    Text("Title (optional)").font(.callout.weight(.medium))
                    TextField("A name you will recognize", text: $session.title)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Title")
                    Text(session.titleLoader.hint)
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(height: 28, alignment: .topLeading)
                } else {
                    Text("The item keeps its existing title.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(height: 96, alignment: .top)
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if session.isPayload {
                    Picker("When invoked", selection: $session.opens) {
                        Text("Open").tag(true)
                        Text("Paste").tag(false)
                    }
                    .pickerStyle(.segmented)
                    Picker("Open with", selection: $session.application) {
                        Text("Default").tag("")
                        ForEach(session.applications) { app in Text(app.name).tag(app.id) }
                    }
                    .opacity(session.opens ? 1 : 0)
                    .disabled(!session.opens)
                    .accessibilityHidden(!session.opens)
                } else {
                    Text("Runs this existing item. Its action stays unchanged.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 72, alignment: .top)
            Text(session.replacement)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(height: 28, alignment: .topLeading)
            Text(session.failure ?? session.issue ?? "Ready. Type the trigger in Tinycast, then press Return.")
                .font(.caption)
                .foregroundStyle(session.failure == nil && session.issue == nil ? Color.secondary : Color.orange)
                .frame(height: 42, alignment: .topLeading)
        }
        .onChange(of: session.target) { _, _ in
            session.failure = nil
            refreshApplications()
            session.titleLoader.refresh(target: session.target)
        }
        .onChange(of: session.trigger) { _, _ in session.failure = nil }
        .onChange(of: session.title) { _, _ in session.failure = nil }
    }
}
