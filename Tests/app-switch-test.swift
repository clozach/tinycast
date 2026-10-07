import Foundation

@main
@MainActor
struct AppSwitchTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: Bool, _ message: String) {
        if condition { passes += 1 } else { failures += 1; print("FAIL: \(message)") }
    }

    static func main() {
        let apps = (1...5).map { AppSwitchEntry(id: Int32($0), name: "App \($0)", bundlePath: nil) }
        let ordered = AppSwitchOrder.sorted(apps.reversed(), recentIDs: [1, 2, 3, 4, 5], initialID: 1)
        expect(ordered.map(\.id) == [2, 1, 3, 4, 5], "recency with only the head pair flipped")
        expect(AppSwitchOrder.sorted(apps, recentIDs: [2, 3, 1], initialID: 1).map(\.id)
            == [2, 1, 3, 4, 5], "the app displaced at the initial trigger is A")
        expect(AppSwitchOrder.sorted(apps, recentIDs: [1, 1, 99, 2, 3, 4, 5], initialID: 1) == ordered,
            "stale and duplicate recency entries do not duplicate running apps")
        expect(AppSwitchOrder.sorted([], recentIDs: [1], initialID: 1).isEmpty, "no apps is safe")
        expect(AppSwitchOrder.sorted([apps[0]], recentIDs: [], initialID: 1) == [apps[0]], "one app stays first")
        expect(AppSwitchOrder.filtered(ordered, query: "app 3").map(\.id) == [3], "normal typing filters apps")
        expect(AppSwitchOrder.filtered(ordered, query: "  ") == ordered, "clearing preserves recency")
        var selection = 0
        var cycle: [Int32] = [ordered[selection].id]
        for _ in 0..<5 {
            selection = AppSwitchOrder.next(from: selection, count: ordered.count, backwards: false) ?? -1
            cycle.append(ordered[selection].id)
        }
        expect(cycle == [2, 1, 3, 4, 5, 2], "B A C D E B loops forward")
        cycle = [ordered[selection].id]
        for _ in 0..<5 {
            selection = AppSwitchOrder.next(from: selection, count: ordered.count, backwards: true) ?? -1
            cycle.append(ordered[selection].id)
        }
        expect(cycle == [2, 5, 4, 3, 1, 2], "Shift loops in the reverse direction")
        expect(AppSwitchOrder.next(from: 0, count: 0, backwards: false) == nil, "empty cycling is safe")
        expect(AppSwitchOrder.next(from: 0, count: 1, backwards: true) == 0, "one app wraps onto itself")

        let trigger = AppSwitchGesture.Trigger(keyCode: 49, modifiers: 1, shift: 2)
        var gesture = AppSwitchGesture()
        gesture.begin(trigger)
        expect(!gesture.isSwitching, "initial trigger does not activate on release")
        expect(gesture.press(keyCode: 49, modifiers: 1) == .repeatPress, "holding Space does not enter")
        expect(!gesture.sample(modifiers: 1, keyIsDown: false), "release Space while holding Command")
        expect(gesture.press(keyCode: 49, modifiers: 1) == .enter, "first subsequent press enters on B")
        expect(gesture.isSwitching, "release activation is armed after entering")
        expect(gesture.press(keyCode: 49, modifiers: 1) == .repeatPress, "duplicate Carbon/local press is harmless")
        gesture.keyReleased()
        expect(gesture.press(keyCode: 49, modifiers: 1) == .step(backwards: false), "second subsequent press advances")
        gesture.keyReleased()
        expect(gesture.press(keyCode: 49, modifiers: 3) == .step(backwards: true), "adding Shift reverses")
        expect(!gesture.sample(modifiers: 0, keyIsDown: true), "Command released before Space does not activate yet")
        expect(gesture.sample(modifiers: 0, keyIsDown: false), "all keys released activates once")
        expect(!gesture.sample(modifiers: 0, keyIsDown: false), "further release notifications cannot activate twice")

        gesture.begin(trigger)
        gesture.keyReleased()
        expect(!gesture.sample(modifiers: 0, keyIsDown: false), "releasing initial modifiers just leaves the palette")
        expect(gesture.press(keyCode: 49, modifiers: 1) == .ignored, "fresh modifiers cannot enter the old gesture")
        gesture.begin(trigger)
        gesture.keyReleased()
        expect(gesture.press(keyCode: 49, modifiers: 3) == .enter, "Shift on the first subsequent trigger still selects B")
        gesture.cancel()
        expect(!gesture.sample(modifiers: 0, keyIsDown: false), "typing, dictation, click or action cancels release activation")
        gesture.begin(trigger)
        gesture.keyReleased()
        expect(gesture.press(keyCode: 0, modifiers: 1) == .ignored, "another key disqualifies the sequence")
        expect(gesture.trigger == nil, "no hidden gesture survives another key")
        gesture.begin(trigger)
        gesture.keyReleased()
        expect(gesture.press(keyCode: 49, modifiers: 5) == .ignored, "an extra non-Shift modifier is another shortcut")
        gesture.begin(trigger)
        gesture.keyReleased()
        expect(gesture.press(keyCode: 49, modifiers: 1, isRepeat: true) == .repeatPress,
            "autorepeat after a release sample still does not enter")
        let multi = AppSwitchGesture.Trigger(keyCode: 5, modifiers: 5, shift: 2)
        gesture.begin(multi)
        gesture.keyReleased()
        expect(gesture.press(keyCode: 5, modifiers: 5) == .enter, "a command shortcut can enter")
        expect(!gesture.sample(modifiers: 1, keyIsDown: false), "partial modifier release in switching waits")
        expect(gesture.sample(modifiers: 0, keyIsDown: false), "the last modifier release commits")
        gesture.begin(multi)
        gesture.keyReleased()
        _ = gesture.press(keyCode: 5, modifiers: 5)
        expect(!gesture.sample(modifiers: 1, keyIsDown: false), "partial release waits without rearming")
        expect(gesture.press(keyCode: 5, modifiers: 5) == .ignored,
            "repressing a modifier cannot extend a gesture whose continuous hold ended")
        expect(!gesture.sample(modifiers: 0, keyIsDown: false), "a disqualified resumed hold cannot activate")
        gesture.begin(trigger)
        gesture.keyReleased()
        _ = gesture.press(keyCode: 49, modifiers: 1)
        expect(!gesture.sample(modifiers: 5, keyIsDown: false), "adding another modifier disqualifies switching")
        expect(gesture.trigger == nil, "a disqualified modifier sequence cannot activate on release")
        gesture.begin(.init(keyCode: 122, modifiers: 0, shift: 2))
        expect(gesture.trigger == nil, "a modifier-free trigger has no held sequence")
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
