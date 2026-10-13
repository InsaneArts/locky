import CoreGraphics
import Foundation

// Prints the id of a window of a process once it exists (waits up to 10 s):
//
//   window-id PID [PREFIX]           a normal window (kCGWindowLayer 0) of PID whose title starts with PREFIX
//                                     (default "Locky Preview"); an empty PREFIX takes the first normal window with any title
//   window-id PID "" --sheet PARENT  a normal window of PID over window PARENT: a sheet
let arguments = Array(CommandLine.arguments.dropFirst())
let pid = Int32(arguments.first ?? "") ?? 0
let prefix = arguments.count > 1 ? arguments[1] : "Locky Preview"
let parent = arguments.count > 3 && arguments[2] == "--sheet" ? Int(arguments[3]) : nil

func number(_ window: [String: Any]) -> Int? { window[kCGWindowNumber as String] as? Int }
func bounds(_ window: [String: Any]) -> CGRect? {
    (window[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
}

for _ in 0..<100 {
    let windows = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []).filter {
        ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
    }
    let found: [String: Any]?
    if let parent {
        // A sheet lies inside its window's bounds.
        let frame = windows.first { number($0) == parent }.flatMap(bounds)?.insetBy(dx: -1, dy: -1)
        found = frame.flatMap { frame in windows.first { number($0) != parent && bounds($0).map(frame.contains) == true } }
    } else {
        found = windows.first { window in
            let title = window[kCGWindowName as String] as? String ?? ""
            return !title.isEmpty && title.hasPrefix(prefix)
        }
    }
    if let found, let id = number(found) {
        print(id)
        exit(0)
    }
    Thread.sleep(forTimeInterval: 0.1)
}
exit(1)
