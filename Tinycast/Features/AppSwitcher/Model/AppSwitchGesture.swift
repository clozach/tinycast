import Foundation

struct AppSwitchGesture: Equatable, Sendable {
    struct Trigger: Equatable, Sendable {
        let keyCode: Int
        let modifiers: UInt64
        let shift: UInt64

        func matches(keyCode: Int, modifiers: UInt64) -> Bool {
            self.keyCode == keyCode && (modifiers == self.modifiers || modifiers == self.modifiers | shift)
        }
    }

    enum KeyState: Equatable, Sendable { case down, up }
    enum State: Equatable, Sendable {
        case idle
        case armed(Trigger, KeyState)
        case switching(Trigger, KeyState)
    }
    enum Action: Equatable { case ignored, repeatPress, enter, step(backwards: Bool) }

    private(set) var state: State = .idle
    private var modifiersReleased = false

    var trigger: Trigger? {
        switch state {
        case .idle: nil
        case .armed(let trigger, _), .switching(let trigger, _): trigger
        }
    }

    var isSwitching: Bool {
        if case .switching = state { return true }
        return false
    }

    mutating func begin(_ trigger: Trigger) {
        modifiersReleased = false
        state = trigger.modifiers == 0 ? .idle : .armed(trigger, .down)
    }

    mutating func cancel() { state = .idle; modifiersReleased = false }

    mutating func press(keyCode: Int, modifiers: UInt64, isRepeat: Bool = false) -> Action {
        guard !modifiersReleased, let trigger, trigger.matches(keyCode: keyCode, modifiers: modifiers) else {
            cancel()
            return .ignored
        }
        switch state {
        case .idle: return .ignored
        case .armed(_, .down), .switching(_, .down): return .repeatPress
        case .armed(_, .up):
            guard !isRepeat else { return .repeatPress }
            state = .switching(trigger, .down)
            return .enter
        case .switching(_, .up):
            guard !isRepeat else { return .repeatPress }
            state = .switching(trigger, .down)
            return .step(backwards: modifiers & trigger.shift != 0)
        }
    }

    mutating func keyReleased() {
        switch state {
        case .idle: break
        case .armed(let trigger, _): state = .armed(trigger, .up)
        case .switching(let trigger, _): state = .switching(trigger, .up)
        }
    }

    /// Release commits only after the trigger key and every momentary modifier are up.
    mutating func sample(modifiers: UInt64, keyIsDown: Bool) -> Bool {
        if let trigger, modifiers & ~(trigger.modifiers | trigger.shift) != 0 {
            cancel()
            return false
        }
        switch state {
        case .idle: return false
        case .armed(let trigger, _):
            guard modifiers & trigger.modifiers == trigger.modifiers else {
                cancel()
                return false
            }
        case .switching(let trigger, _):
            if modifiers & trigger.modifiers != trigger.modifiers { modifiersReleased = true }
            if modifiers == 0, !keyIsDown {
                cancel()
                return true
            }
        }
        if !keyIsDown { keyReleased() }
        return false
    }
}
