import Foundation

/// Runs a short-lived CLI to completion and returns its full stdout.
///
/// `ProcessRunner` is line-oriented and built for long conversions with
/// live progress; for one-shot probes (`ffprobe -of json`, `magick
/// identify`) we want the whole stdout as one blob, read to EOF so nothing
/// is lost if the process exits before a `readabilityHandler` fires.
enum ProcessOutputCapture {
    static func stdout(executable: URL, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                // Drain stderr concurrently so a chatty tool can't fill the
                // pipe buffer and deadlock while we block on stdout.
                let stderrBox = LockedBox(Data())
                let stderrDone = DispatchGroup()
                stderrDone.enter()
                DispatchQueue.global(qos: .utility).async {
                    let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    stderrBox.withLock { $0 = data }
                    stderrDone.leave()
                }

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                stderrDone.wait()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    continuation.resume(returning: String(decoding: stdoutData, as: UTF8.self))
                } else {
                    let stderrText = stderrBox.withLock { String(decoding: $0, as: UTF8.self) }
                    continuation.resume(throwing: ProcessRunnerError.nonZeroExit(
                        code: process.terminationStatus, stderr: stderrText
                    ))
                }
            }
        }
    }
}
