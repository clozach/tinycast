import Foundation

/// How far the system lets us narrow a sound: to this window, only to its app, or not at all.
enum AudioPlayback: Sendable, Equatable {
    case silent
    case app
    case window

    var isAudible: Bool { self != .silent }

    var help: String {
        switch self {
        case .silent: ""
        case .app: "This app is playing audio"
        case .window: "This window is playing audio"
        }
    }
}

/// What one window's controls reveal. Pure data, so attribution needs no accessibility API.
struct WindowAudioProbe: Sendable, Equatable {
    var hasMarker = false
    var hasTabStrip = false
}

enum AudioMarker {
    /// Chromium titles a playing tab "… - Audio playing"; Safari gives it a "Mute This Tab" button.
    static func indicatesAudio(_ label: String) -> Bool {
        let text = label.lowercased()
        return text.contains("audio playing") || text.hasPrefix("mute this tab")
            || text.hasPrefix("mute tab")
    }
}

enum AudioAttribution {
    /// A marked window wins. With no marker anywhere, an app without tabs owns all its windows;
    /// a browser whose tabs show no marker (muted, or unreadable) is left unattributed.
    static func playback(of probes: [WindowAudioProbe], appPlaying: Bool) -> [AudioPlayback] {
        guard appPlaying else { return probes.map { _ in .silent } }
        if probes.contains(where: \.hasMarker) { return probes.map { $0.hasMarker ? .window : .silent } }
        if probes.contains(where: \.hasTabStrip) { return probes.map { _ in .silent } }
        return probes.map { _ in .app }
    }
}

/// A made-up loudness envelope: fast, irregular, always in 0…1, from the clock alone.
enum AudioPulse {
    private static let rates: [(hertz: Double, weight: Double)] = [(4.3, 0.5), (7.9, 0.3), (13.1, 0.2)]

    static func level(at time: TimeInterval) -> Double {
        let sum = rates.reduce(0.0) { $0 + $1.weight * sin(2 * .pi * $1.hertz * time) }
        return (sum + 1) / 2
    }
}
