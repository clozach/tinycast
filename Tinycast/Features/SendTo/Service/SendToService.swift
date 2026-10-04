import AppKit

@MainActor
enum SendToService {
    struct RunningApp: Equatable {
        let pid: Int32
        let name: String
        let url: URL?
    }

    @MainActor
    struct Sources {
        var openers: @MainActor (URL) -> [URL] = { NSWorkspace.shared.urlsForApplications(toOpen: $0) }
        var defaultOpener: @MainActor (URL) -> URL? = { NSWorkspace.shared.urlForApplication(toOpen: $0) }
        var appIdentity: @MainActor (URL) -> String? = { Bundle(url: $0)?.bundleIdentifier }
        var running: @MainActor () -> [RunningApp] = SendToService.runningApps
        var ownPID: Int32 = ProcessInfo.processInfo.processIdentifier
    }

    @MainActor
    struct Environment {
        var pasteboard: NSPasteboard = .general
        var canPaste: @MainActor () -> Bool = Permissions.ensureAccessibility
        var activate: @MainActor (Int32) -> Bool = { pid in
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return false }
            return app.activate()
        }
        var frontmost: @MainActor () -> Int32? = { NSWorkspace.shared.frontmostApplication?.processIdentifier }
        var postPaste: @MainActor (Int32) -> Void = { Paster.postCommandV(toPid: $0) }
        var sleep: @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
        var open: @MainActor ([URL], URL) async throws -> Void = { items, app in
            _ = try await NSWorkspace.shared.open(items, withApplicationAt: app, configuration: .init())
        }
    }

    static func targets(for payload: SendToPayload, sources: Sources = Sources()) throws -> [SendToTarget] {
        try validate(payload)
        let items = payload.openItems
        var openers: [URL] = []
        if let first = items.first {
            let others = items.dropFirst().map { Set(sources.openers($0).map(\.standardizedFileURL)) }
            var seen = Set<URL>()
            openers = sources.openers(first).map(\.standardizedFileURL).filter { app in
                others.allSatisfy { $0.contains(app) } && seen.insert(app).inserted
            }
            if let preferred = sources.defaultOpener(first)?.standardizedFileURL,
               let index = openers.firstIndex(of: preferred) {
                openers.insert(openers.remove(at: index), at: 0)
            }
            var identities = Set<String>()
            openers = openers.filter { app in
                let identity = sources.appIdentity(app).flatMap { $0.isEmpty ? nil : "bundle:\($0)" }
                    ?? "path:\(app.path)"
                return identities.insert(identity).inserted
            }
        }
        var seenPIDs = Set<Int32>()
        let running = sources.running().filter { $0.pid != sources.ownPID && seenPIDs.insert($0.pid).inserted }
        return openers.map { .open(app: $0, items: items) } +
            running.map { .paste(pid: $0.pid, name: $0.name, app: $0.url) }
    }

    static func send(
        _ payload: SendToPayload, to target: SendToTarget, environment: Environment = Environment()
    ) async throws {
        try Task.checkCancellation()
        try validate(payload)
        switch target {
        case .open(let app, let items):
            guard !items.isEmpty else { throw SendToError.emptyPayload }
            try await environment.open(items, app)
        case .paste(let pid, let name, _):
            guard environment.canPaste() else { throw SendToError.accessibility }
            try write(payload, to: environment.pasteboard)
            let writtenCount = environment.pasteboard.changeCount
            if environment.frontmost() != pid, !environment.activate(pid) {
                throw SendToError.appUnavailable(name)
            }
            for _ in 0..<38 {
                try Task.checkCancellation()
                if environment.frontmost() == pid {
                    try await environment.sleep(.milliseconds(60))
                    try Task.checkCancellation()
                    if environment.frontmost() == pid {
                        if environment.pasteboard.changeCount != writtenCount {
                            try write(payload, to: environment.pasteboard)
                        }
                        environment.postPaste(pid)
                        return
                    }
                }
                try await environment.sleep(.milliseconds(40))
            }
            throw SendToError.activationTimedOut(name)
        }
    }

    static func runningApps() -> [RunningApp] {
        let own = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != own
        }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        var order: [Int32: Int] = [:]
        for window in windows where window[kCGWindowLayer as String] as? Int == 0 {
            if let pid = window[kCGWindowOwnerPID as String] as? Int32, order[pid] == nil { order[pid] = order.count }
        }
        if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier { order[front] = -1 }
        return apps.sorted {
            let lhs = order[$0.processIdentifier] ?? Int.max
            let rhs = order[$1.processIdentifier] ?? Int.max
            return lhs != rhs ? lhs < rhs : ($0.localizedName ?? "") < ($1.localizedName ?? "")
        }.map { RunningApp(pid: $0.processIdentifier, name: $0.localizedName ?? "App", url: $0.bundleURL) }
    }

    static func validate(_ payload: SendToPayload) throws {
        switch payload {
        case .text(let value): if value.isEmpty { throw SendToError.emptyPayload }
        case .files(let urls): if urls.isEmpty { throw SendToError.emptyPayload }
        case .pasteboard(let snapshot): if snapshot.items.isEmpty { throw SendToError.emptyPayload }
        case .image: break
        }
        for url in payload.openItems where url.isFileURL {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw SendToError.unavailableFile(url.lastPathComponent)
            }
        }
    }
}
