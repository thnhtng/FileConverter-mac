import XCTest
@testable import FileConverterKit

/// Argument shapes for the Spec Check fix fields. The exact ffmpeg
/// command lines were also run by hand against ffmpeg 6.1 (pad to
/// 1080x1920 + fps 30 + silent audio + -t 10 -> probed 1080x1920, 30 fps,
/// aac, 10.0 s); `SpecCheckIntegrationTests` covers them end to end.
final class SpecFixArgumentTests: XCTestCase {
    let input = URL(fileURLWithPath: "/tmp/in.mov")
    let output = URL(fileURLWithPath: "/tmp/out.mp4")

    private func mp4Args(_ configure: (inout VideoSettings) -> Void) throws -> [String] {
        var preset = DefaultPresets.preset(for: .mp4)
        var video = try XCTUnwrap(preset.settings.video)
        configure(&video)
        preset.settings = .video(video)
        return try FFmpegArgumentBuilder.passes(for: preset, inputURL: input, outputURL: output)[0].arguments
    }

    private func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    func testDefaultsAreUnchangedWithoutFixFields() throws {
        let args = try mp4Args { _ in }
        XCTAssertEqual(value(after: "-vf", in: args), "format=yuv420p")
        XCTAssertFalse(args.contains("-maxrate"))
        XCTAssertFalse(args.contains("-t"))
        XCTAssertFalse(args.contains("-movflags"))
        XCTAssertEqual(args.filter { $0 == "-i" }.count, 1)
    }

    func testPadFilterForcesEvenSizes() throws {
        let args = try mp4Args { $0.frameTarget = FrameTarget(width: 1081, height: 1921, fitMode: .pad) }
        XCTAssertEqual(
            value(after: "-vf", in: args),
            "scale=1080:1920:force_original_aspect_ratio=decrease:force_divisible_by=2,"
                + "pad=1080:1920:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1,format=yuv420p"
        )
        XCTAssertEqual(value(after: "-movflags", in: args), "+faststart")
    }

    func testCropAndFpsFilters() throws {
        let args = try mp4Args {
            $0.frameTarget = FrameTarget(width: 1080, height: 1080, fitMode: .crop)
            $0.framesPerSecond = 30
        }
        XCTAssertEqual(
            value(after: "-vf", in: args),
            "scale=1080:1080:force_original_aspect_ratio=increase:force_divisible_by=2,crop=1080:1080,setsar=1,fps=30,format=yuv420p"
        )
    }

    func testBitrateCapDurationAndSilentAudio() throws {
        let args = try mp4Args {
            $0.maxVideoBitrateKbps = 2000
            $0.maxDurationSeconds = 10
            $0.addSilentAudioIfMissing = true
        }
        XCTAssertEqual(value(after: "-maxrate", in: args), "2000k")
        XCTAssertEqual(value(after: "-bufsize", in: args), "4000k")
        XCTAssertEqual(value(after: "-t", in: args), "10.000")
        XCTAssertEqual(args.filter { $0 == "-i" }.count, 2)
        XCTAssertEqual(value(after: "-f", in: args), "lavfi")
        XCTAssertTrue(args.contains("-shortest"))
        XCTAssertEqual(args.suffix(1), [output.path])
        // The silent source must be input #1, right after the real input.
        let firstInput = try XCTUnwrap(args.firstIndex(of: "-i"))
        XCTAssertEqual(args[firstInput + 1], input.path)
        XCTAssertEqual(args[firstInput + 2], "-f")
    }

    func testSilentAudioIgnoredWhenAudioDisabled() throws {
        let args = try mp4Args {
            $0.enableAudio = false
            $0.addSilentAudioIfMissing = true
        }
        XCTAssertTrue(args.contains("-an"))
        XCTAssertFalse(args.contains("lavfi"))
        XCTAssertFalse(args.contains("-map"))
    }

    func testWebmBitrateCapUsesConstrainedQuality() throws {
        var preset = DefaultPresets.preset(for: .webm)
        var video = try XCTUnwrap(preset.settings.video)
        video.maxVideoBitrateKbps = 900
        preset.settings = .video(video)
        let args = try FFmpegArgumentBuilder.passes(for: preset, inputURL: input, outputURL: URL(fileURLWithPath: "/tmp/o.webm"))[0].arguments
        XCTAssertEqual(value(after: "-b:v", in: args), "900k")
        XCTAssertTrue(args.contains("-crf"))
    }

    func testImageMagickFrameTargetArgs() throws {
        var preset = DefaultPresets.preset(for: .jpg)
        var image = try XCTUnwrap(preset.settings.image)
        image.frameTarget = FrameTarget(width: 1290, height: 2796, fitMode: .crop)
        preset.settings = .image(image)
        let plan = try ImageMagickArgumentBuilder.plan(
            for: preset, inputURL: URL(fileURLWithPath: "/tmp/a.png"), outputURL: URL(fileURLWithPath: "/tmp/a.jpg")
        )
        let joined = plan.arguments.joined(separator: " ")
        XCTAssertTrue(joined.contains("-resize 1290x2796^ -gravity center -extent 1290x2796 +repage"), joined)

        XCTAssertEqual(
            ImageMagickArgumentBuilder.frameTargetArgs(FrameTarget(width: 10, height: 20, fitMode: .pad)),
            ["-resize", "10x20", "-background", "black", "-gravity", "center", "-extent", "10x20", "+repage"]
        )
        XCTAssertEqual(ImageMagickArgumentBuilder.frameTargetArgs(FrameTarget(width: 10, height: 20, fitMode: .stretch)), ["-resize", "10x20!"])
    }
}
