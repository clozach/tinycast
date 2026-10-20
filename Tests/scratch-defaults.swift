import Foundation

/// cfprefsd rewrites a suite under ~/Library/Preferences after the process exits, so a path in a
/// folder of its own is the only suite a harness can leave nothing behind.
func scratchSuiteName(_ label: String) -> String {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("tinycast-\(label)-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("suite").path
}

func discardSuite(_ name: String, _ defaults: UserDefaults) {
    defaults.removePersistentDomain(forName: name)
    let folder = URL(fileURLWithPath: name).deletingLastPathComponent()
    guard folder.lastPathComponent.hasPrefix("tinycast-") else { return }
    try? FileManager.default.removeItem(at: folder)
}
