import XCTest
@testable import FileConverterKit

/// End to end with real ffmpeg: probe -> check (fails) -> plan fix -> run
/// the fix through `ConversionQueue` -> probe the output -> check (passes).
/// Skips when ffmpeg isn't installed.
final class SpecCheckIntegrationTests: XCTestCase {
    var workDir: URL!

    override func setUpWithError() throws {
        try XCTSkipIf(BinaryLocator.locate(.ffmpeg) == nil || BinaryLocator.locate(.ffprobe) == nil, "ffmpeg/ffprobe not installed")
        workDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let workDir { try? FileManager.default.removeItem(at: workDir) }
    }

    /// Landscape, 60 fps, no audio track, 12 s — wrong for a vertical ad.
    private func makeLandscapeClip(seconds: Int = 12) async throws -> URL {
        let ffmpeg = try XCTUnwrap(BinaryLocator.locate(.ffmpeg))
        let url = workDir.appendingPathComponent("landscape.mp4")
        try await ProcessRunner().run(executable: ffmpeg, arguments: [
            "-y", "-f", "lavfi", "-i", "testsrc=duration=\(seconds):size=640x360:rate=60",
            "-c:v", "libx264", "-preset", "ultrafast", url.path
        ])
        return url
    }

    private func runFix(_ plan: SpecFixPlan, on input: URL) async throws -> URL {
        let queue = ConversionQueue(maxConcurrency: 1)
        let id = await queue.enqueue(inputURL: input, preset: plan.preset)
        await queue.runAll()
        let status = await queue.status(for: id)
        XCTAssertEqual(status?.state, .done, status?.errorDescription ?? "")
        return try XCTUnwrap(status?.outputURLs.first)
    }

    func testProbeReadsRealFile() async throws {
        let clip = try await makeLandscapeClip()
        let info = try await MediaProbe.probe(clip)
        XCTAssertEqual(info.kind, .video)
        XCTAssertEqual(info.width, 640)
        XCTAssertEqual(info.height, 360)
        XCTAssertEqual(info.framesPerSecond ?? 0, 60, accuracy: 0.01)
        XCTAssertEqual(info.durationSeconds ?? 0, 12, accuracy: 0.1)
        XCTAssertEqual(info.videoCodec, "h264")
        XCTAssertFalse(info.hasAudio)
        XCTAssertGreaterThan(info.fileSizeBytes, 0)
    }

    func testFixMakesLandscapeClipPassVerticalSpec() async throws {
        var spec = DefaultSpecs.verticalVideoAd
        spec.width = 360          // keep the test encode small
        spec.height = 640
        spec.maxFramesPerSecond = 30
        spec.maxDurationSeconds = 8
        spec.maxFileSizeMB = 1

        let clip = try await makeLandscapeClip()
        let before = try await SpecCheckService.check(clip, against: spec)
        XCTAssertEqual(
            Set(before.failures.map(\.rule)),
            [.dimensions, .aspectRatio, .duration, .frameRate, .audioTrack]
        )

        let plan = try SpecFixPlanner.plan(for: before, spec: spec).get()
        let fixed = try await runFix(plan, on: clip)
        XCTAssertEqual(fixed.lastPathComponent, "landscape_fixed.mp4")

        let after = try await SpecCheckService.check(fixed, against: spec)
        XCTAssertEqual(after.status, .pass, "\(after.findings.filter { $0.status != .pass })")
        XCTAssertEqual(after.info.displayWidth, 360)
        XCTAssertEqual(after.info.displayHeight, 640)
        XCTAssertTrue(after.info.hasAudio)
        XCTAssertEqual(after.info.durationSeconds ?? 0, 8, accuracy: 0.2)
    }

    func testCropModeAndSizeCap() async throws {
        let spec = DeliverySpec(
            name: "square small", mediaKinds: [.video], maxFileSizeMB: 0.25,
            aspectRatios: [.square1x1], audio: .forbidden
        )
        let clip = try await makeLandscapeClip(seconds: 6)
        let before = try await SpecCheckService.check(clip, against: spec)
        XCTAssertTrue(before.failures.contains { $0.rule == .aspectRatio })

        let plan = try SpecFixPlanner.plan(for: before, spec: spec, options: SpecFixOptions(fitMode: .crop)).get()
        XCTAssertEqual(plan.preset.settings.video?.frameTarget, FrameTarget(width: 360, height: 360, fitMode: .crop))
        let fixed = try await runFix(plan, on: clip)

        let after = try await SpecCheckService.check(fixed, against: spec)
        XCTAssertEqual(after.status, .pass, "\(after.findings.filter { $0.status != .pass })")
        XCTAssertFalse(after.info.hasAudio)
    }
}
