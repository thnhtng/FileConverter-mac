import XCTest
@testable import FileConverterKit

/// Real end-to-end smoke tests — actually shells out to ffmpeg, per the
/// plan's Phase 1 verification step ("CLI-only harness ... checks the
/// output file exists and is non-empty"). Skips (not fails) if ffmpeg isn't
/// installed on the machine running the tests, since CI/dev environments
/// vary.
final class FFmpegIntegrationTests: XCTestCase {
    var workDir: URL!

    override func setUpWithError() throws {
        try XCTSkipIf(BinaryLocator.locate(.ffmpeg) == nil, "ffmpeg not installed, skipping integration test")
        workDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDir)
    }

    /// Generates a tiny synthetic video (1s, color bars + tone) via
    /// ffmpeg's `lavfi` input so the test has no external asset dependency.
    private func makeSampleVideo() async throws -> URL {
        guard let ffmpeg = BinaryLocator.locate(.ffmpeg) else { throw XCTSkip() }
        let output = workDir.appendingPathComponent("sample.mp4")
        let runner = ProcessRunner()
        try await runner.run(executable: ffmpeg, arguments: [
            "-y", "-f", "lavfi", "-i", "testsrc=duration=1:size=64x64:rate=10",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
            "-c:v", "libx264", "-preset", "ultrafast", "-c:a", "aac",
            output.path
        ])
        return output
    }

    func testConvertToMp3ProducesNonEmptyFile() async throws {
        let sample = try await makeSampleVideo()
        let preset = DefaultPresets.preset(for: .mp3)
        let output = workDir.appendingPathComponent("out.mp3")

        try await FFmpegConversionExecutor().execute(preset: preset, inputURL: sample, outputURL: output)

        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        let size = try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 0)
    }

    func testConvertToMkvProducesNonEmptyFile() async throws {
        let sample = try await makeSampleVideo()
        let preset = DefaultPresets.preset(for: .mkv)
        let output = workDir.appendingPathComponent("out.mkv")

        try await FFmpegConversionExecutor().execute(preset: preset, inputURL: sample, outputURL: output)

        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        let size = try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 0)
    }

    func testConvertToGifProducesNonEmptyFileAndCleansUpPalette() async throws {
        let sample = try await makeSampleVideo()
        let preset = DefaultPresets.preset(for: .gif)
        let output = workDir.appendingPathComponent("out.gif")

        try await FFmpegConversionExecutor().execute(preset: preset, inputURL: sample, outputURL: output)

        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        let paletteFiles = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
            .filter { $0.contains("sample.mp4 - palette") }
        XCTAssertTrue(paletteFiles.isEmpty, "palette temp file should be cleaned up after conversion")
    }

    func testFullQueuePipelineEndToEnd() async throws {
        let sample = try await makeSampleVideo()
        let queue = ConversionQueue(maxConcurrency: 2)
        let id = await queue.enqueue(inputURL: sample, preset: DefaultPresets.preset(for: .mp3))
        await queue.runAll()

        let status = await queue.status(for: id)
        XCTAssertEqual(status?.state, .done)
        XCTAssertEqual(status?.progress, 1)
        XCTAssertEqual(status?.outputURLs.count, 1)
        if let outputURL = status?.outputURLs.first {
            XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        }
    }
}
