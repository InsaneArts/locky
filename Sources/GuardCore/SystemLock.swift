import Darwin
import Foundation

/// The macOS lock screen: what Locky switches to when it cannot keep the lock itself.
public enum SystemLock {
    /// SACLockScreenImmediate, the call behind the Apple menu's Lock Screen, in the private login framework.
    /// nil if a macOS release removes it.
    public static func resolve() -> (@convention(c) () -> Int32)? {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_LAZY),
              let symbol = dlsym(handle, "SACLockScreenImmediate") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) () -> Int32).self)
    }

    /// Locks the Mac now. false when the call is missing.
    @discardableResult
    public static func engage(reason: String) -> Bool {
        #if DEBUG
        // Tests: a line in this file instead of a real lock. Release builds never read it.
        if let path = ProcessInfo.processInfo.environment["LOCKY_SYSTEM_LOCK_FILE"] {
            let file = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
            guard file >= 0 else { return false }
            defer { close(file) }
            let line = Array("lock: \(reason)\n".utf8)
            return write(file, line, line.count) == line.count
        }
        #endif
        guard let lock = resolve() else { return false }
        _ = lock()
        return true
    }
}
