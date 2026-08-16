import XCTest
@testable import FileConverterKit

final class FFmpegArgumentBuilderTests: XCTestCase {
    let input = URL(fileURLWithPath: "/tmp/input.mov")
    let output = URL(fileURLWithPath: "/tmp/output.mp4")

    func testMp4UsesH264DefaultsAndCRF23() throws {
        let preset = DefaultPresets.preset(for: .mp4)
        let passes = try FFmpegArgumentBuilder.passes(for: preset, inputURL: input, outputURL: output)
        XCTAssertEqual(passes.count, 1)
        let args = passes[0].arguments
        XCTAssertTrue(args.contains("libx264"))
        XCTAssertTrue(args.contains("-crf"))
        XCTAssertEqual(args[args.firstIndex(of: "-crf")! + 1], "23")
        XCTAssertTrue(args.contains("-preset"))
        XCTAssertEqual(args[args.firstIndex(of: "-preset")! + 1], "medium")
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains(input.path))
        XCTAssertEqual(args.last, output.path)
    }

    func testMp4WithoutAudioAddsAnFlag() throws {
        var preset = DefaultPresets.preset(for: .mp4)
        guard case .video(var video) = preset.settings else { return XCTFail() }
        video.enableAudio = false
        preset.settings = .video(video)

        let args = try FFmpegArgumentBuilder.passes(for: preset, inputURL: input, outputURL: output)[0].arguments
        XCTAssertTrue(args.contains("-an"))
        XCTAssertFalse(args.contains("-c:a"))
    }

    func testGifProducesTwoPassesWithPaletteCleanup() throws {
        let preset = DefaultPresets.preset(for: .gif)
        let gifOutput = URL(fileURLWithPath: "/tmp/output.gif")
        let passes = try FFmpegArgumentBuilder.passes(for: preset, inputURL: input, outputURL: gifOutput)
        XCTAssertEqual(passes.count, 2)
        XCTAssertNotNil(passes[0].fileToDelete)
        XCTAssertTrue(passes[0].arguments.contains(where: { $0.contains("palettegen") }))
        XCTAssertTrue(passes[1].arguments.contains(where: { $0.contains("paletteuse") }))
    }

    func testWebmLosslessAtQuality63() throws {
        var preset = DefaultPresets.preset(for: .webm)
        guard case .video(var video) = preset.settings else { return XCTFail() }
        video.quality = 63
        preset.settings = .video(video)

        let webmOutput = URL(fileURLWithPath: "/tmp/output.webm")
        let args = try FFmpegArgumentBuilder.passes(for: preset, inputURL: input, outputURL: webmOutput)[0].arguments
        XCTAssertTrue(args.contains("-lossless"))
        XCTAssertFalse(args.contains("-crf"))
    }

    func testImageOutputTypesAreRejectedByFFmpegBuilder() throws {
        let preset = DefaultPresets.preset(for: .png)
        XCTAssertThrowsError(try FFmpegArgumentBuilder.passes(for: preset, inputURL: input, outputURL: URL(fileURLWithPath: "/tmp/o.png"))) { error in
            XCTAssertEqual(error as? FFmpegArgumentBuilderError, .unsupportedOutputType(.png))
        }
    }

    func testUnrecognizedBitrateThrows() throws {
        var preset = DefaultPresets.preset(for: .mp3)
        guard case .audio(var audio) = preset.settings else { return XCTFail() }
        audio.bitrateKbps = 123
        preset.settings = .audio(audio)

        XCTAssertThrowsError(try FFmpegArgumentBuilder.passes(for: preset, inputURL: input, outputURL: URL(fileURLWithPath: "/tmp/o.mp3"))) { error in
            XCTAssertEqual(error as? FFmpegArgumentBuilderError, .unrecognizedBitrate(123))
        }
    }

    func testRotationAndScaleFilterGraph() {
        let transform = FFmpegTransform(scale: 0.5, rotationDegrees: 90)
        XCTAssertEqual(transform.filterGraph(), "scale=iw*0.5:ih*0.5,transpose=2")
    }

    func testMkvForcesEvenDimensionsAndYUV420P() {
        let transform = FFmpegTransform(scale: 1, rotationDegrees: 0, forceEvenDimensionsAndYUV420P: true)
        XCTAssertEqual(transform.filterGraph(), "format=yuv420p")
    }
}
