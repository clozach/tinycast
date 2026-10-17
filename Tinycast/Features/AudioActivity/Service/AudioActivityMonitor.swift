import AppKit

/// Which running apps are playing sound, polled only while the palette is up.
@MainActor
@Observable
final class AudioActivityMonitor {
    private(set) var playingProcessIDs: Set<pid_t> = []
    private(set) var playingBundleIDs: Set<String> = []
    @ObservationIgnored private var polling: Task<Void, Never>?
    private static let interval: Duration = .milliseconds(500)

    func isPlaying(processID: pid_t) -> Bool { playingProcessIDs.contains(processID) }

    func isPlaying(bundleID: String?) -> Bool {
        bundleID.map(playingBundleIDs.contains) ?? false
    }

    func start() {
        guard polling == nil else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                let owners = await Task.detached(priority: .utility) {
                    AudioProcessReader.owningOutputProcessIDs()
                }.value
                self?.publish(owners)
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    func stop() {
        polling?.cancel()
        polling = nil
        publish([])
    }

    private func publish(_ owners: Set<pid_t>) {
        guard owners != playingProcessIDs else { return }
        playingProcessIDs = owners
        playingBundleIDs = Set(owners.compactMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier })
    }
}
