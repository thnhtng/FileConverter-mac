import XCTest
@testable import FileConverterKit

final class SpecFixPlannerTests: XCTestCase {
    private func video(width: Int = 1920, height: Int = 1080, duration: Double = 20, fps: Double = 30, sizeMB: Double = 10, ext: String = "mp4", audio: Bool = true) -> MediaInfo {
        MediaInfo(
            fileURL: URL(fileURLWithPath: "/tmp/clip.\(ext)"), fileSizeBytes: Int64(sizeMB * 1_000_000), kind: .video,
            width: width, height: height, durationSeconds: duration, framesPerSecond: fps,
            videoCodec: "h264", audioCodec: audio ? "aac" : nil, hasAudio: audio
        )
    }

    private func plan(_ info: MediaInfo, _ spec: DeliverySpec, fit: FrameFitMode = .pad) -> Result<SpecFixPlan, SpecFixUnavailableReason> {
        SpecFixPlanner.plan(for: SpecChecker.check(info, against: spec), spec: spec, options: SpecFixOptions(fitMode: fit))
    }

    func testLandscapeToVerticalPadsToExactSize() throws {
        let fix = try plan(video(), DefaultSpecs.verticalVideoAd).get()
        XCTAssertEqual(fix.preset.outputType, .mp4)
        XCTAssertEqual(fix.preset.outputFileNameTemplate, "(p)(f)_fixed")
        let settings = try XCTUnwrap(fix.preset.settings.video)
        XCTAssertEqual(settings.frameTarget, FrameTarget(width: 1080, height: 1920, fitMode: .pad))
        XCTAssertTrue(settings.enableAudio)
        XCTAssertNil(settings.addSilentAudioIfMissing)
        XCTAssertTrue(fix.actions.contains { $0.contains("black bars") }, "\(fix.actions)")
    }

    func testMissingAudioAddsSilentTrackAndLongClipIsTrimmed() throws {
        let fix = try plan(video(width: 1080, height: 1920, duration: 90, audio: false), DefaultSpecs.verticalVideoAd).get()
        let settings = try XCTUnwrap(fix.preset.settings.video)
        XCTAssertEqual(settings.addSilentAudioIfMissing, true)
        XCTAssertEqual(settings.maxDurationSeconds, 60)
        XCTAssertNil(settings.frameTarget, "dimensions already pass")
    }

    func testBitrateCapIsAimedAtSizeLimit() throws {
        let spec = DeliverySpec(name: "small", mediaKinds: [.video], maxFileSizeMB: 5, audio: .optional)
        let fix = try plan(video(duration: 20, sizeMB: 12), spec).get()
        let settings = try XCTUnwrap(fix.preset.settings.video)
        // 5 MB * 8000 kbit/MB * 0.9 headroom / 20 s = 1800 kbps total, minus 128 kbps audio.
        XCTAssertEqual(settings.maxVideoBitrateKbps, 1672)
        XCTAssertEqual(settings.audioBitrateKbps, 128)
        XCTAssertTrue(fix.actions.contains { $0.contains("1672 kbps") })
    }

    func testTightBudgetDropsAudioBitrateThenGivesUp() throws {
        let spec = DeliverySpec(name: "tiny", mediaKinds: [.video], maxFileSizeMB: 1, audio: .optional)
        // 1 MB over 20 s = 360 kbps total -> 64 kbps audio, 296 video.
        let fix = try plan(video(duration: 20, sizeMB: 12), spec).get()
        XCTAssertEqual(fix.preset.settings.video?.audioBitrateKbps, 64)
        XCTAssertEqual(fix.preset.settings.video?.maxVideoBitrateKbps, 296)

        // 1 MB over 120 s isn't watchable — refuse instead of producing mush.
        let tooLong = DeliverySpec(name: "tiny", mediaKinds: [.video], maxFileSizeMB: 1, audio: .optional)
        XCTAssertEqual(
            plan(video(duration: 120, sizeMB: 12), tooLong),
            .failure(.sizeLimitTooSmall(maxMB: 1, durationSeconds: 120))
        )
    }

    func testFrameRateIsLowered() throws {
        var spec = DefaultSpecs.verticalVideoAd
        spec.maxFramesPerSecond = 30
        let fix = try plan(video(width: 1080, height: 1920, fps: 60), spec).get()
        XCTAssertEqual(fix.preset.settings.video?.framesPerSecond, 30)
    }

    func testTooShortCannotBeFixed() {
        XCTAssertEqual(
            plan(video(width: 1080, height: 1920, duration: 3), DefaultSpecs.verticalVideoAd),
            .failure(.tooShort(actualSeconds: 3, minimumSeconds: 5))
        )
    }

    func testMovOnlySpecHasNoProducibleFormat() {
        let spec = DeliverySpec(name: "mov", mediaKinds: [.video], allowedExtensions: ["mov"])
        XCTAssertEqual(plan(video(ext: "avi"), spec), .failure(.noSupportedOutputFormat(allowed: ["mov"])))
    }

    func testVP9OnlySpecPicksWebm() throws {
        let spec = DeliverySpec(name: "vp9", mediaKinds: [.video], allowedVideoCodecs: ["vp9"])
        XCTAssertEqual(try plan(video(), spec).get().preset.outputType, .webm)
    }

    func testPassingFileHasNothingToFix() {
        let ok = video(width: 1080, height: 1920)
        XCTAssertEqual(plan(ok, DefaultSpecs.verticalVideoAd), .failure(.nothingToFix))
    }

    func testRatioOnlySpecGrowsForPadAndShrinksForCrop() {
        let spec = DeliverySpec(name: "square", mediaKinds: [.video], aspectRatios: [.square1x1])
        let info = video(width: 1920, height: 1080)
        let padded = SpecFixPlanner.targetFrameSize(info: info, spec: spec, fitMode: .pad, evenDimensions: true)
        XCTAssertEqual(padded?.width, 1920)
        XCTAssertEqual(padded?.height, 1920)
        let cropped = SpecFixPlanner.targetFrameSize(info: info, spec: spec, fitMode: .crop, evenDimensions: true)
        XCTAssertEqual(cropped?.width, 1080)
        XCTAssertEqual(cropped?.height, 1080)
    }

    func testBoundsScaleUniformlyAndStayEven() {
        let spec = DeliverySpec(name: "max720", mediaKinds: [.video], maxWidth: 1280, maxHeight: 720)
        let size = SpecFixPlanner.targetFrameSize(info: video(width: 1921, height: 1081), spec: spec, fitMode: .pad, evenDimensions: true)
        XCTAssertEqual(size?.width, 1278)
        XCTAssertEqual(size?.height, 720)
    }

    func testImageSwitchesPngToJpgForSizeAndResizes() throws {
        let image = MediaInfo(fileURL: URL(fileURLWithPath: "/tmp/shot.png"), fileSizeBytes: 12_000_000, kind: .image, width: 1170, height: 2532)
        let fix = try plan(image, DefaultSpecs.storeScreenshotPortrait, fit: .crop).get()
        XCTAssertEqual(fix.preset.outputType, .jpg)
        XCTAssertEqual(fix.preset.settings.image?.frameTarget, FrameTarget(width: 1290, height: 2796, fitMode: .crop))
        XCTAssertEqual(fix.preset.settings.image?.quality, 80)
    }

    func testAudioFilesAreNotAutoFixable() {
        let audio = MediaInfo(fileURL: URL(fileURLWithPath: "/tmp/a.wav"), fileSizeBytes: 50_000_000, kind: .audio, durationSeconds: 10)
        XCTAssertEqual(plan(audio, DefaultSpecs.chatAttachment), .failure(.unsupportedMediaKind(.audio)))
    }
}
