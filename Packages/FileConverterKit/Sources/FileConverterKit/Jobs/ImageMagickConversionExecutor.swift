import Foundation

/// Runs the plan built by `ImageMagickArgumentBuilder`. Handles the
/// multi-page-PDF-input case by querying the page count via `magick
/// identify` first (ConversionJob_ImageMagick.cs `GetOutputFilesCount`
/// equivalent), then returning every produced page file.
public struct ImageMagickConversionExecutor {
    public init() {}

    @discardableResult
    public func execute(
        preset: ConversionPreset,
        inputURL: URL,
        outputURL: URL,
        progress: ConversionProgressHandler? = nil
    ) async throws -> [URL] {
        guard let magick = BinaryLocator.locate(.magick) else {
            throw ConversionJobError.binaryNotFound("magick")
        }

        let pageCount = try await pageCount(of: inputURL, magick: magick)
        let plan = try ImageMagickArgumentBuilder.plan(
            for: preset, inputURL: inputURL, outputURL: outputURL, inputPageCount: pageCount
        )

        let runner = ProcessRunner()
        try await runner.run(executable: magick, arguments: plan.arguments)
        progress?(1)

        if plan.producesMultiplePages {
            let ext = outputURL.pathExtension
            let stem = outputURL.deletingPathExtension().lastPathComponent
            let directory = outputURL.deletingLastPathComponent()
            return (0..<pageCount).map { index in
                directory.appendingPathComponent(String(format: "\(stem)-%02d.\(ext)", index))
            }
        }

        return [outputURL]
    }

    private func pageCount(of url: URL, magick: URL) async throws -> Int {
        guard url.pathExtension.lowercased() == "pdf" else { return 1 }
        let runner = ProcessRunner()
        let linesBox = LockedBox<[String]>([])
        do {
            _ = try await runner.run(executable: magick, arguments: ["identify", url.path]) { line in
                linesBox.withLock { $0.append(line) }
            }
        } catch {
            return 1
        }
        return max(1, linesBox.withLock { $0.filter { !$0.isEmpty }.count })
    }
}
