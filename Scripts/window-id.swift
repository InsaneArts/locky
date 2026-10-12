import CoreGraphics
import Foundation

// Prints the id of the window titled <prefix>… (default "Locky Preview") that process <pid> shows, once it
// exists (waits up to 10 s).
let arguments = Array(CommandLine.arguments.dropFirst())
let pid = Int32(arguments.first ?? "") ?? 0
let prefix = arguments.count > 1 ? arguments[1] : "Locky Preview"
for _ in 0..<100 {
    let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    if let window = windows.first(where: {
        ($0[kCGWindowOwnerPID as String] as? Int32) == pid && (($0[kCGWindowName as String] as? String)?.hasPrefix(prefix) ?? false)
    }) {
        print(window[kCGWindowNumber as String]!)
        exit(0)
    }
    Thread.sleep(forTimeInterval: 0.1)
}
exit(1)
