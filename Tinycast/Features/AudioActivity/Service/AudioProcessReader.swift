import CoreAudio
import Foundation

/// Which processes the system says are rendering sound right now, without tapping any audio.
enum AudioProcessReader {
    private typealias ResponsibleFunction = @convention(c) (pid_t) -> pid_t
    private static let responsible: ResponsibleFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
        else { return nil }
        return unsafeBitCast(symbol, to: ResponsibleFunction.self)
    }()

    /// Output-running processes mapped to the app that owns them: a browser's helper is the browser.
    nonisolated static func owningOutputProcessIDs() -> Set<pid_t> {
        Set(outputProcessIDs().map(owner(of:)))
    }

    nonisolated static func outputProcessIDs() -> Set<pid_t> {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = property(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return Set(objects.compactMap { object in
            guard flag(kAudioProcessPropertyIsRunningOutput, of: object) else { return nil }
            return pid(of: object)
        })
    }

    /// The process itself when the system names no other responsible one.
    nonisolated static func owner(of pid: pid_t) -> pid_t {
        guard let responsible else { return pid }
        let found = responsible(pid)
        return found > 0 ? found : pid
    }

    private nonisolated static func property(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
    }

    private nonisolated static func flag(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> Bool {
        var address = property(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    private nonisolated static func pid(of object: AudioObjectID) -> pid_t? {
        var address = property(kAudioProcessPropertyPID)
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }
}
