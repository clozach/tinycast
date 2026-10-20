import Foundation

enum AppPaths {
    static func applicationSupport() -> URL { FileManager.default.temporaryDirectory }
}

enum Permissions {
    static func hasFullDiskAccess() -> Bool { false }
}

private actor IndexBuilderProbe {
    private var outputs: [String] = []
    private var shouldFail = false

    func failNext(_ fail: Bool) { shouldFail = fail }
    func calls() -> [String] { outputs }

    func build(_ request: FileSearchPolicy.Request, output: URL) -> Bool {
        outputs.append(output.lastPathComponent)
        guard !shouldFail else { return false }
        let original = FileSearchPolicy(request)
        let crawling = FileSearchPolicy(
            scopes: request.scopes,
            ignorePatterns: request.ignorePatterns
                + (output.lastPathComponent == "readable-index.bin" ? ["protected-marker.txt"] : []),
            homeDirectory: original.homeDirectory)
        let roots = FileIndexCrawler.roots(of: crawling)
        guard !roots.isEmpty else { return false }
        let listings = FileIndexCrawler.Crawl(roots: roots, policy: crawling).run(workers: 2)
        do {
            try FileManager.default.createDirectory(
                at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileIndexSnapshot.write(
                listings, roots: roots, eventID: 0, fingerprint: original.fingerprint, to: output)
            return true
        } catch {
            return false
        }
    }
}

@main @MainActor
struct FileSearchIndexerTests {
    private final class Grant { var allowed = false }
    private static var failures = 0

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { failures += 1; print("FAIL: \(message)") }
    }

    private static func waitUntil(_ done: () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !done(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
        expect(done(), "the indexer finishes its requested transition")
    }

    static func main() async throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appending(path: "file-search-access-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: scratch) }
        let root = scratch.appending(path: "home")
        let cache = scratch.appending(path: "cache")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["visible-marker.txt", "protected-marker.txt"] {
            try Data("fixture".utf8).write(to: root.appending(path: name))
        }
        let policy = FileSearchPolicy(scopes: [root.path], ignorePatterns: [], homeDirectory: root)
        let probe = IndexBuilderProbe()
        let full = cache.appending(path: FileSearchAccess.full.indexFileName)
        _ = await probe.build(policy.request, output: full)
        let grant = Grant()
        let indexer = FileIndexer(
            directory: cache, accessProbe: { grant.allowed },
            buildOperation: { request, output, _ in await probe.build(request, output: output) })
        indexer.apply(policy)
        indexer.setEnabled(true)
        await waitUntil { indexer.hasIndex }
        expect(indexer.access == .limited, "no FDA still builds a limited index")
        expect(!fm.fileExists(atPath: full.path), "limited startup removes the older full-access cache")
        expect(names(indexer, "visible-marker").count == 1, "readable search remains useful")
        expect(names(indexer, "protected-marker").isEmpty, "full-access cache is not served without FDA")

        grant.allowed = true
        indexer.refreshAccess()
        expect(!indexer.hasIndex, "a permission transition immediately drops the old map")
        await waitUntil { indexer.hasIndex }
        expect(indexer.access == .full, "grant updates coverage")
        expect(names(indexer, "protected-marker").count == 1, "grant rebuilds protected content")

        grant.allowed = false
        indexer.refreshAccess()
        expect(
            !indexer.hasIndex && names(indexer, "protected-marker").isEmpty,
            "revocation clears protected results immediately")
        await waitUntil { indexer.hasIndex }
        expect(names(indexer, "protected-marker").isEmpty, "revocation rebuilds readable-only content")
        expect(!fm.fileExists(atPath: full.path), "revocation drops the full-access disk cache")
        let calls = await probe.calls()
        expect(
            calls == ["index.bin", "readable-index.bin", "index.bin", "readable-index.bin"],
            "access changes choose distinct cache outputs")

        await probe.failNext(true)
        indexer.rebuild()
        await waitUntil { indexer.status == .failed }
        expect(indexer.hasIndex, "a failed rebuild keeps the usable readable index")
        await probe.failNext(false)
        indexer.apply(FileSearchPolicy(scopes: [], ignorePatterns: [], homeDirectory: root))
        await waitUntil {
            if case .ready(items: 0, builtAt: _) = indexer.status { return true }
            return false
        }
        expect(
            !indexer.hasIndex && names(indexer, "visible-marker").isEmpty,
            "clearing scopes clears previous results")
        let beforeEmptyRebuild = await probe.calls()
        indexer.rebuild()
        try? await Task.sleep(for: .milliseconds(150))
        let afterEmptyRebuild = await probe.calls()
        expect(beforeEmptyRebuild == afterEmptyRebuild, "rebuilding empty scopes never launches a helper")
        indexer.setEnabled(false)
        expect(indexer.status == .off && !indexer.hasIndex, "off clears the mapped index")
        expect(!fm.fileExists(atPath: cache.path), "off removes both cache modes")
        print(failures == 0 ? "File search indexer tests passed" : "\(failures) file search indexer failures")
        exit(failures == 0 ? 0 : 1)
    }

    private static func names(_ indexer: FileIndexer, _ query: String) -> [String] {
        indexer.index.search(FileSearchQuery.prepare(query)!, filter: .all).map(\.name)
    }
}
