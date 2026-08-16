import Foundation

/// Probes input duration via `ffprobe`, used to turn `FFmpegProgress`'s
/// `out_time_us` into a 0-1 fraction. The Windows app instead parsed
/// ffmpeg's own "Duration: HH:MM:SS.CC" stderr line
/// (ConversionJob_FFMPEG.cs durationRegex) — ffprobe's structured output is
/// more robust and avoids depending on stderr at all.
public enum FFprobeDurationProbe {
    public static func duration(of inputURL: URL) async -> Double? {
        guard let ffprobe = BinaryLocator.locate(.ffprobe) else { return nil }
        let runner = ProcessRunner()
        var output = ""
        do {
            output = try await runWithStdoutCapture(runner: runner, executable: ffprobe, arguments: [
                "-v", "error",
                "-show_entries", "format=duration",
                "-of", "default=noprint_wrappers=1:nokey=1",
                inputURL.path
            ])
        } catch {
            return nil
        }
        return Double(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func runWithStdoutCapture(runner: ProcessRunner, executable: URL, arguments: [String]) async throws -> String {
        let linesBox = LockedBox<[String]>([])
        _ = try await runner.run(executable: executable, arguments: arguments) { line in
            linesBox.withLock { $0.append(line) }
        }
        return linesBox.withLock { $0.joined(separator: "\n") }
    }
}
