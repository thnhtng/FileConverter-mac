import XCTest
@testable import FileConverterKit

final class SpecCheckerTests: XCTestCase {
    private func video(
        _ name: String = "ad.mp4",
        width: Int = 1080, height: Int = 1920, rotation: Int = 0,
        duration: Double = 15, fps: Double = 30,
        sizeMB: Double = 10, codec: String = "h264",
        audio: String? = "aac"
    ) -> MediaInfo {
        MediaInfo(
            fileURL: URL(fileURLWithPath: "/tmp/\(name)"),
            fileSizeBytes: Int64(sizeMB * 1_000_000),
            kind: .video,
            width: width, height: height, rotationDegrees: rotation,
            durationSeconds: duration, framesPerSecond: fps,
            videoCodec: codec, audioCodec: audio, hasAudio: audio != nil
        )
    }

    private func status(_ result: SpecCheckResult, _ rule: SpecRule) -> SpecFindingStatus? {
        result.findings.first { $0.rule == rule }?.status
    }

    func testCompliantVerticalVideoPassesEveryRule() {
        let result = SpecChecker.check(video(), against: DefaultSpecs.verticalVideoAd)
        XCTAssertEqual(result.status, .pass, "\(result.findings)")
        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(
            Set(result.findings.map(\.rule)),
            [.mediaKind, .fileFormat, .fileSize, .dimensions, .aspectRatio, .duration, .frameRate, .videoCodec, .audioTrack, .audioCodec]
        )
    }

    func testLandscapeVideoFailsDimensionsAndRatioWithReadableValues() {
        let result = SpecChecker.check(video(width: 1920, height: 1080), against: DefaultSpecs.verticalVideoAd)
        XCTAssertEqual(result.status, .fail)
        let dims = result.findings.first { $0.rule == .dimensions }
        XCTAssertEqual(dims?.status, .fail)
        XCTAssertEqual(dims?.expected, "1080 × 1920")
        XCTAssertEqual(dims?.actual, "1920 × 1080")
        let ratio = result.findings.first { $0.rule == .aspectRatio }
        XCTAssertEqual(ratio?.expected, "9:16")
        XCTAssertEqual(ratio?.actual, "16:9")
    }

    func testRotationFlagIsRespected() {
        // Phone footage stored 1920x1080 with a 90° display matrix is
        // actually a vertical video.
        let result = SpecChecker.check(video(width: 1920, height: 1080, rotation: 90), against: DefaultSpecs.verticalVideoAd)
        XCTAssertEqual(status(result, .dimensions), .pass)
        XCTAssertEqual(status(result, .aspectRatio), .pass)
    }

    func testSizeDurationFpsCodecAndAudioFailures() {
        let info = video(duration: 75, fps: 120, sizeMB: 45, codec: "hevc", audio: nil)
        let result = SpecChecker.check(info, against: DefaultSpecs.verticalVideoAd)
        XCTAssertEqual(status(result, .fileSize), .fail)
        XCTAssertEqual(status(result, .duration), .fail)
        XCTAssertEqual(status(result, .frameRate), .fail)
        XCTAssertEqual(status(result, .videoCodec), .fail)
        XCTAssertEqual(status(result, .audioTrack), .fail)
        XCTAssertNil(status(result, .audioCodec), "no audio stream, so no audio codec rule")
        XCTAssertEqual(result.findings.first { $0.rule == .duration }?.expected, "5 s – 60 s")
    }

    func testNtscFrameRateCountsAsThirty() {
        var spec = DefaultSpecs.verticalVideoAd
        spec.maxFramesPerSecond = 30
        XCTAssertEqual(status(SpecChecker.check(video(fps: 29.97), against: spec), .frameRate), .pass)
        XCTAssertEqual(status(SpecChecker.check(video(fps: 30.0), against: spec), .frameRate), .pass)
        XCTAssertEqual(status(SpecChecker.check(video(fps: 50), against: spec), .frameRate), .fail)
    }

    func testWrongMediaKindShortCircuits() {
        let image = MediaInfo(fileURL: URL(fileURLWithPath: "/tmp/a.png"), fileSizeBytes: 1000, kind: .image, width: 10, height: 10)
        let result = SpecChecker.check(image, against: DefaultSpecs.verticalVideoAd)
        XCTAssertEqual(result.findings.map(\.rule), [.mediaKind])
        XCTAssertEqual(result.status, .fail)
    }

    func testUnknownValuesBecomeWarningsNotFailures() {
        var info = video()
        info.width = nil
        info.height = nil
        info.durationSeconds = nil
        let result = SpecChecker.check(info, against: DefaultSpecs.verticalVideoAd)
        XCTAssertEqual(status(result, .dimensions), .warning)
        XCTAssertEqual(status(result, .aspectRatio), .warning)
        XCTAssertEqual(status(result, .duration), .warning)
        XCTAssertEqual(result.status, .warning)
        XCTAssertTrue(result.passed)
    }

    func testExtensionMatchingIsCaseInsensitiveAndTreatsJpegAsJpg() {
        let image = MediaInfo(fileURL: URL(fileURLWithPath: "/tmp/Shot.JPEG"), fileSizeBytes: 1000, kind: .image, width: 1290, height: 2796)
        let result = SpecChecker.check(image, against: DefaultSpecs.storeScreenshotPortrait)
        XCTAssertEqual(status(result, .fileFormat), .pass)
        XCTAssertEqual(result.status, .pass)
    }

    func testMinMaxBounds() {
        let spec = DeliverySpec(name: "bounds", mediaKinds: [.image], minWidth: 600, minHeight: 600, maxWidth: 2000, maxHeight: 2000)
        func check(_ w: Int, _ h: Int) -> SpecFindingStatus? {
            let info = MediaInfo(fileURL: URL(fileURLWithPath: "/tmp/a.png"), fileSizeBytes: 1, kind: .image, width: w, height: h)
            return status(SpecChecker.check(info, against: spec), .dimensions)
        }
        XCTAssertEqual(check(1000, 1000), .pass)
        XCTAssertEqual(check(500, 1000), .fail)
        XCTAssertEqual(check(1000, 2500), .fail)
    }

    func testForbiddenAudio() {
        let spec = DeliverySpec(name: "silent", mediaKinds: [.video], audio: .forbidden)
        XCTAssertEqual(status(SpecChecker.check(video(audio: "aac"), against: spec), .audioTrack), .fail)
        XCTAssertEqual(status(SpecChecker.check(video(audio: nil), against: spec), .audioTrack), .pass)
    }

    func testSizeOnlySpecAppliesToAnyFile() {
        let doc = MediaInfo(fileURL: URL(fileURLWithPath: "/tmp/deck.pdf"), fileSizeBytes: 30_000_000, kind: .document)
        let result = SpecChecker.check(doc, against: DefaultSpecs.chatAttachment)
        XCTAssertEqual(result.findings.map(\.rule), [.fileSize])
        XCTAssertEqual(result.status, .fail)
        XCTAssertEqual(result.findings[0].actual, "30 MB")
    }

    func testDescribeRatio() {
        XCTAssertEqual(SpecChecker.describeRatio(width: 1920, height: 1080), "16:9")
        XCTAssertEqual(SpecChecker.describeRatio(width: 1290, height: 2796), "0.46:1")
        XCTAssertEqual(SpecChecker.describeRatio(width: 1000, height: 1000), "1:1")
    }
}
