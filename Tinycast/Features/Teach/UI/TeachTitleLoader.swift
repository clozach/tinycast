import Foundation

/// Owns title suggestions and their lifetime independently of the form's other fields.
@MainActor @Observable
final class TeachTitleLoader {
    enum Status { case idle, loading, found, unavailable }
    private(set) var status = Status.idle
    private var value: String
    private var edited: Bool
    private var generation = 0
    private var task: Task<String?, Never>?
    private let fetch: @Sendable (URL) async -> String?

    init(title: String?, fetch: @escaping @Sendable (URL) async -> String? = PageTitleFetcher.fetch) {
        value = title ?? ""
        edited = !(title ?? "").isEmpty
        self.fetch = fetch
    }

    var title: String {
        get { value }
        set { value = newValue; edited = true; cancel(); status = .idle }
    }

    var hint: String {
        switch status {
        case .loading: "Looking up the page title. You can save now."
        case .unavailable: "No page title found. Add a title or keep the trigger as its name."
        case .idle, .found: "Shown in results. Your trigger stays the same."
        }
    }

    @discardableResult
    func refresh(target: String) -> Task<String?, Never>? {
        cancel()
        guard !edited else { return nil }
        value = ""
        guard let url = PageTitle.url(target) else { status = .idle; return nil }
        status = .loading
        let expectedGeneration = generation
        task = Task { [weak self, fetch] in
            let result = await fetch(url)
            guard let self, !Task.isCancelled, generation == expectedGeneration, !edited else { return nil }
            if let result { value = result }
            status = result == nil ? .unavailable : .found
            return result
        }
        return task
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
    }

    /// Saving never waits. A later result is metadata for that exact unchanged save only.
    @discardableResult
    func completeAfterSave(_ target: TaughtTarget, store: TeachStore) -> Task<Void, Never>? {
        guard target.title == nil, !edited, let pending = task else { cancel(); return nil }
        task = nil
        let revision = store.revision
        return Task { [self, weak store] in
            guard let title = await pending.value, !edited, let store, store.revision == revision,
                store.target(entryID: target.entryID) == target else { return }
            var titled = target
            titled.title = title
            try? store.save(titled)
        }
    }
}
