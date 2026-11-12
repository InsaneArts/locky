import Foundation

/// What a short-lived program writes to standard output, read with a time limit.
enum ProgramOutput {
    /// Runs `program` with `arguments`, standard input and error going nowhere, and returns its standard output. nil
    /// when it cannot start, or when it takes longer than `timeout` seconds, which stops it. A program it started that
    /// keeps the pipe open after it ends (a login shell's profile can leave one) makes the read give up the same way.
    static func read(_ program: String, _ arguments: [String], timeout: Double) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: program)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        nonisolated(unsafe) var data = Data()
        let read = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            data = output.fileHandleForReading.readDataToEndOfFile()
            read.signal()
        }
        guard read.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            return nil
        }
        return data
    }
}
