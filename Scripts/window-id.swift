import CoreGraphics
import Foundation

// Prints the id of the titled window that process <pid> shows, once it exists (waits up to 10 s).
let pid = Int32(CommandLine.arguments.dropFirst().first ?? "") ?? 0
for _ in 0..<100 {
    let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    if let window = windows.first(where: {
        ($0[kCGWindowOwnerPID as String] as? Int32) == pid && (($0[kCGWindowName as String] as? String)?.hasPrefix("Locky Preview") ?? false)
    }) {
        print(window[kCGWindowNumber as String]!)
        exit(0)
    }
    Thread.sleep(forTimeInterval: 0.1)
}
exit(1)
