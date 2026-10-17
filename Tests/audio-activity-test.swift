import Foundation

@main
@MainActor
struct AudioActivityTests {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        markers()
        attribution()
        pulse()
        liveReader()
        if failures > 0 { exit(1) }
        print("audio-activity-test: all checks passed")
    }

    static func markers() {
        expect(AudioMarker.indicatesAudio("Ad – YouTube - Audio playing - Memory usage - 41.0 MB"),
            "a Chromium tab named for its sound is audible")
        expect(AudioMarker.indicatesAudio("Mute This Tab"), "Safari's mute button marks the playing tab")
        expect(!AudioMarker.indicatesAudio("Unmute This Tab"), "a muted Safari tab is silent")
        expect(!AudioMarker.indicatesAudio("Audio muted"), "a muted Chromium tab is silent")
        expect(!AudioMarker.indicatesAudio("Tab bar, 2 tabs"), "the tab bar itself is not a marker")
        expect(!AudioMarker.indicatesAudio(""), "an empty label is not a marker")
    }

    static func attribution() {
        let marked = WindowAudioProbe(hasMarker: true, hasTabStrip: true)
        let tabs = WindowAudioProbe(hasMarker: false, hasTabStrip: true)
        let plain = WindowAudioProbe()
        expect(AudioAttribution.playback(of: [tabs, marked], appPlaying: true) == [.silent, .window],
            "only the window with the marker is audible")
        expect(AudioAttribution.playback(of: [marked, marked], appPlaying: true) == [.window, .window],
            "several marked windows are all audible")
        expect(AudioAttribution.playback(of: [plain, plain], appPlaying: true) == [.app, .app],
            "an app without tabs owns its sound in every window")
        expect(AudioAttribution.playback(of: [tabs, tabs], appPlaying: true) == [.silent, .silent],
            "a browser with no marker stays unattributed")
        expect(AudioAttribution.playback(of: [marked, plain], appPlaying: false) == [.silent, .silent],
            "a silent app marks no window, whatever its controls say")
        expect(AudioAttribution.playback(of: [], appPlaying: true).isEmpty, "no windows, no states")
    }

    static func pulse() {
        let samples = stride(from: 0.0, to: 5.0, by: 0.02).map(AudioPulse.level(at:))
        expect(samples.allSatisfy { (0...1).contains($0) }, "the envelope stays within 0…1")
        expect((samples.max() ?? 0) - (samples.min() ?? 1) > 0.6, "the envelope swings widely")
        expect(AudioPulse.level(at: 1.234) == AudioPulse.level(at: 1.234), "the envelope is a pure function")
    }

    static func liveReader() {
        let mine = getpid()
        expect(AudioProcessReader.owner(of: mine) == mine || AudioProcessReader.owner(of: mine) > 0,
            "an owner always resolves to a real process")
        expect(!AudioProcessReader.owningOutputProcessIDs().contains(0), "no output process is pid 0")
    }
}
