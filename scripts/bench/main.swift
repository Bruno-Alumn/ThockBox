// Performance checks for ThockBox: CPU per key press with the menu views
// alive (as in the real app), idle CPU right after typing, and idle CPU once
// the audio engine has paused.
//
// Run via `make bench`. It compiles the app's sources (minus the @main
// entry point) together with this file and runs a real AppKit event loop,
// outside `make test` so the test suite stays fast.
// Settings and keystroke counts go to this tool's own defaults domain
// (thockbox-bench), not the app's. Exits non-zero on a large regression.

import AppKit
import SwiftUI

let sounds = URL(fileURLWithPath: CommandLine.arguments[1])
let maxMicrosPerKey = 1_800.0   // ~1,050 µs today, including playing the sound
let maxIdlePercent = 2.0        // ~0.6% today
let maxPausedPercent = 0.3      // ~0% today: the engine pauses after 30 s without sound

func cpuSeconds() -> Double {
    var r = rusage()
    getrusage(RUSAGE_SELF, &r)
    return Double(r.ru_utime.tv_sec + r.ru_stime.tv_sec)
        + Double(r.ru_utime.tv_usec + r.ru_stime.tv_usec) / 1e6
}

/// Stands in for the menu bar label in ThockboxApp, which observes AppState.
struct BarLabel: View {
    @ObservedObject var state: AppState
    var body: some View { Image(systemName: state.enabled ? "keyboard.fill" : "keyboard") }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let state = AppState.shared
state.volume = 0
if let pack = SoundPack.discover(in: sounds).first { state.engine.load(pack: pack) }
try state.engine.start()

let windows = [AnyView(BarLabel(state: state)), AnyView(MenuView(state: state))].map { view in
    let w = NSWindow(contentRect: .init(x: 0, y: 0, width: 300, height: 700),
                     styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = NSHostingView(rootView: view)
    w.orderOut(nil)   // hidden, like a closed menu
    return w
}

var failed = false
let keys = 1_000
var sent = 0

func measureIdle() {
    // Let the last sounds finish and every voice go idle, then measure.
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        let start = cpuSeconds()
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            let percent = (cpuSeconds() - start) / 10 * 100
            print(String(format: "idle after typing:  %5.2f%% CPU      (limit %.0f%%)", percent, maxIdlePercent))
            failed = failed || percent > maxIdlePercent
            measurePaused()
        }
    }
}

/// Skips the 30 s wait by asking the engine to pause as if it had passed.
func measurePaused() {
    state.engine.pauseIfIdle(now: Date().addingTimeInterval(SoundEngine.idlePauseDelay + 1))
    guard state.engine.isIdlePaused else {
        print("idle when paused:   skipped (Bluetooth-like output never pauses)")
        finish()
        return
    }
    let start = cpuSeconds()
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
        let percent = (cpuSeconds() - start) / 10 * 100
        print(String(format: "idle when paused:   %5.2f%% CPU      (limit %.1f%%)", percent, maxPausedPercent))
        failed = failed || percent > maxPausedPercent
        // The next key has to wake the engine and still play.
        if !state.engine.playKey(keyClass: .row2, up: false, x: 0.5) || state.engine.isIdlePaused {
            print("FAIL: a key after the pause didn't play")
            failed = true
        }
        finish()
    }
}

func finish() {
    print(failed ? "FAIL: performance regressed" : "OK")
    exit(failed ? 1 : 0)
}

DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
    let start = cpuSeconds()
    Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { timer in
        let code: UInt16 = [0, 1, 2, 12, 13, 14][sent % 6]
        state.handle(.keyDown(keycode: code, isRepeat: false, flags: []))
        state.handle(.keyUp(keycode: code))
        sent += 1
        guard sent == keys else { return }
        timer.invalidate()
        let micros = (cpuSeconds() - start) / Double(keys) * 1e6
        print(String(format: "per key press:      %5.0f µs CPU    (limit %.0f µs, %d keys at 100/s)",
                     micros, maxMicrosPerKey, keys))
        failed = micros > maxMicrosPerKey
        measureIdle()
    }
}

_ = windows
app.run()
