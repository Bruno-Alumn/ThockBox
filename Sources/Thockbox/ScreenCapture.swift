import Foundation

/// Whether something is capturing the screen: screen sharing in a call, a
/// screen recording, QuickTime. macOS has no public way to ask, so this uses
/// CoreGraphics' long-standing CGSIsScreenWatcherPresent, looked up at run
/// time: if a future macOS drops it, sharing is simply never detected.
enum ScreenCapture {
    private typealias Query = @convention(c) () -> Bool

    private static let query: Query? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
              let symbol = dlsym(handle, "CGSIsScreenWatcherPresent") else { return nil }
        return unsafeBitCast(symbol, to: Query.self)
    }()

    static var isAvailable: Bool { query != nil }
    static var isActive: Bool { query?() ?? false }
}
