import Foundation

/// Runs the ffmpeg pass(es) built by `FFmpegArgumentBuilder`. Ported from
/// ConversionJob_FFMPEG.cs `Convert()` (multi-pass loop) — cooperative
/// cancellation and per-pass temp-file cleanup included, hooked up to a real
/// process runner instead of the stderr-regex progress path.
public struct FFmpegConversionExecutor {
    public init() {}

    public func execute(
        preset: ConversionPreset,
        inputURL: URL,
        outputURL: URL,
        progress: ConversionProgressHandler? = nil
    ) async throws {
        guard let ffmpeg = BinaryLocator.locate(.ffmpeg) else {
            throw ConversionJobError.binaryNotFound("ffmpeg")
        }

        let passes = try FFmpegArgumentBuilder.passes(for: preset, inputURL: inputURL, outputURL: outputURL)
        let totalDuration = await FFprobeDurationProbe.duration(of: inputURL) ?? 0

        var filesToDelete: [URL] = []
        defer {
            for url in filesToDelete {
                try? FileManager.default.removeItem(at: url)
            }
        }

        for (index, pass) in passes.enumerated() {
            if let fileToDelete = pass.fileToDelete { filesToDelete.append(fileToDelete) }

            let runner = ProcessRunner()
            let progressBox = LockedBox(FFmpegProgress())
            let passFraction = 1.0 / Double(passes.count)
            let baseFraction = Double(index) * passFraction

            do {
                try await runner.run(executable: ffmpeg, arguments: pass.arguments) { line in
                    let withinPass: Double = progressBox.withLock { progress in
                        progress.consume(line: line)
                        return progress.fraction(totalDurationSeconds: totalDuration)
                    }
                    guard totalDuration > 0 else { return }
                    progress?(min(1, baseFraction + withinPass * passFraction))
                }
            } catch let ProcessRunnerError.nonZeroExit(code, stderrText) {
                throw ProcessRunnerError.nonZeroExit(code: code, stderr: Self.trimmedErrorTail(stderrText))
            }
        }

        progress?(1)
    }

    /// The Windows app string-matches specific benign warnings out of
    /// stderr (ConversionJob_FFMPEG.cs:528-541, e.g. issue #247's false
    /// positive on filenames containing "Error"). We don't need that
    /// heuristic since success/failure here comes from the exit code, not
    /// stderr content — this just keeps thrown error messages short.
    private static func trimmedErrorTail(_ stderr: String, maxLines: Int = 20) -> String {
        stderr.split(separator: "\n").suffix(maxLines).joined(separator: "\n")
    }
}
