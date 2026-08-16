import Foundation

/// Parses ffmpeg's machine-readable `-progress pipe:1` output (key=value
/// lines on stdout). Deliberately replaces the Windows app's stderr-regex
/// scraping (ConversionJob_FFMPEG.cs:494-543) — see the plan's Phase 1 notes
/// on why: this format is stable/documented, unlike human-readable stderr.
public struct FFmpegProgress: Sendable {
    public var outTimeMicroseconds: Int64 = 0
    public var isFinished = false
    public var speed: String?

    /// Feed one line of `-progress pipe:1` stdout at a time. Returns true if
    /// this line completed a progress "frame" (progress= key seen), and
    /// updated `outTimeMicroseconds`/`isFinished` accordingly.
    public mutating func consume(line: String) {
        let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        let key = parts[0].trimmingCharacters(in: .whitespaces)
        let value = parts[1].trimmingCharacters(in: .whitespaces)

        switch key {
        case "out_time_us", "out_time_ms":
            outTimeMicroseconds = Int64(value) ?? outTimeMicroseconds
        case "progress":
            isFinished = (value == "end")
        case "speed":
            speed = value
        default:
            break
        }
    }

    /// Fraction in [0, 1], given the total duration of the input (from a
    /// prior `ffprobe`/duration probe — see `FFmpegConversionJob`).
    public func fraction(totalDurationSeconds: Double) -> Double {
        guard totalDurationSeconds > 0 else { return 0 }
        let elapsedSeconds = Double(outTimeMicroseconds) / 1_000_000
        return min(1, max(0, elapsedSeconds / totalDurationSeconds))
    }
}
