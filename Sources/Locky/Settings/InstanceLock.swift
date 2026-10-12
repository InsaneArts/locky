import Foundation

/// The lock that makes one Locky the user's: an exclusive flock on a file in Application Support, held for the
/// life of the process. macOS lets it go when the process ends, however it ends.
enum InstanceLock {
    nonisolated(unsafe) private static var descriptor: Int32 = -1

    static var defaultFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Locky/instance.lock")
    }

    /// True when this process holds the lock now; false when another Locky does. A file that cannot be opened
    /// counts as held here: better a second Locky than none.
    static func acquire(_ file: URL = defaultFile) -> Bool {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(file.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return true }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return false
        }
        descriptor = fd
        return true
    }
}
