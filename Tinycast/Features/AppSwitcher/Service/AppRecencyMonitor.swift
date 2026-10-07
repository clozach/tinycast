import AppKit

@MainActor
final class AppRecencyMonitor {
    private(set) var recentIDs: [pid_t] = []
    private var observer: NotificationToken?

    init() {
        recentIDs = WindowZOrder.appRanks().sorted { $0.value < $1.value }.map(\.key)
        record(NSWorkspace.shared.frontmostApplication)
        let center = NSWorkspace.shared.notificationCenter
        let token = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor [weak self] in self?.record(app) }
        }
        observer = NotificationToken(token, center: center)
    }

    func entries(initialID: pid_t?) -> [AppSwitchEntry] {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != NSRunningApplication.current.processIdentifier
        }
        let entries = apps.map {
            AppSwitchEntry(
                id: $0.processIdentifier, name: $0.localizedName ?? "Application \($0.processIdentifier)",
                bundlePath: $0.bundleURL?.path)
        }
        return AppSwitchOrder.sorted(entries, recentIDs: recentIDs, initialID: initialID)
    }

    private func record(_ app: NSRunningApplication?) {
        guard let app, app.activationPolicy == .regular,
            app.processIdentifier != NSRunningApplication.current.processIdentifier
        else { return }
        let liveIDs = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        recentIDs.removeAll { $0 == app.processIdentifier || !liveIDs.contains($0) }
        recentIDs.insert(app.processIdentifier, at: 0)
    }
}
