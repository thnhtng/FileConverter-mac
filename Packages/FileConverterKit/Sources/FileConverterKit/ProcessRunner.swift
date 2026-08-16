import Foundation

public enum ProcessRunnerError: Error {
    case executableNotFound(String)
    case nonZeroExit(code: Int32, stderr: String)
    case cancelled
}

/// Thin async wrapper around Foundation.Process — replaces the Windows app's
/// `System.Diagnostics.Process` usage (ConversionJob_FFMPEG.cs:78-84,428-492).
/// Kept as a standalone type (not a protocol) for now; a protocol seam can be
/// added if/when tests need to mock process execution without touching the
/// filesystem.
public actor ProcessRunner {
    private var process: Process?
    private var cancelled = false

    public init() {}

    /// Runs `executable` with `arguments`, invoking `onStdoutLine` for every
    /// line written to stdout (used for ffmpeg's `-progress pipe:1` and
    /// ImageMagick's structured progress, when available). Throws
    /// `.nonZeroExit` with the captured stderr tail on failure.
    @discardableResult
    public func run(
        executable: URL,
        arguments: [String],
        onStdoutLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        if cancelled { throw ProcessRunnerError.cancelled }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        self.process = process

        let stderrBox = LockedBox(Data())
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            stderrBox.withLock { $0.append(data) }
        }

        let stdoutBox = LockedBox(Data())
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let lines: [String] = stdoutBox.withLock { buffer in
                buffer.append(data)
                var lines: [String] = []
                while let newlineRange = buffer.range(of: Data([0x0A])) {
                    let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                    buffer.removeSubrange(buffer.startIndex..<newlineRange.upperBound)
                    if let line = String(data: lineData, encoding: .utf8) {
                        lines.append(line)
                    }
                }
                return lines
            }
            for line in lines { onStdoutLine?(line) }
        }

        try process.run()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { proc in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let stderrText = stderrBox.withLock { String(data: $0, encoding: .utf8) ?? "" }
                    continuation.resume(throwing: ProcessRunnerError.nonZeroExit(code: proc.terminationStatus, stderr: stderrText))
                }
            }
        }

        self.process = nil
        return stderrBox.withLock { String(data: $0, encoding: .utf8) ?? "" }
    }

    /// Cooperative cancellation, matching the Windows app's cancel-checked-
    /// per-output-line model (ConversionJob.cs `CancelIsRequested`) — the
    /// process is killed outright since ffmpeg/ImageMagick/soffice have no
    /// graceful "stop now" signal.
    public func cancel() {
        cancelled = true
        process?.terminate()
    }
}
