import XCTest
@testable import FileConverterKit

final class ConversionJobFactoryTests: XCTestCase {
    func testOfficeDocumentsAlwaysRouteToOfficePipelineRegardlessOfOutputType() {
        XCTAssertEqual(ConversionJobFactory.pipeline(forInputExtension: "docx", outputType: .pdf), .office)
        XCTAssertEqual(ConversionJobFactory.pipeline(forInputExtension: "xlsx", outputType: .png), .office)
        XCTAssertEqual(ConversionJobFactory.pipeline(forInputExtension: "ppt", outputType: .jpg), .office)
    }

    func testImageOutputTypesRouteToImageMagick() {
        for outputType: OutputType in [.avif, .jpg, .pdf, .png, .webp] {
            XCTAssertEqual(ConversionJobFactory.pipeline(forInputExtension: "mov", outputType: outputType), .imageMagick)
        }
    }

    func testIcoRoutesToIcoPipeline() {
        XCTAssertEqual(ConversionJobFactory.pipeline(forInputExtension: "png", outputType: .ico), .ico)
    }

    func testAudioVideoOutputTypesRouteToFFmpeg() {
        for outputType: OutputType in [.aac, .avi, .flac, .gif, .mkv, .mp3, .mp4, .ogg, .ogv, .wav, .webm] {
            XCTAssertEqual(ConversionJobFactory.pipeline(forInputExtension: "mov", outputType: outputType), .ffmpeg)
        }
    }

    func testCdaIsUnsupported() {
        guard case .unsupported = ConversionJobFactory.pipeline(forInputExtension: "cda", outputType: .mp3) else {
            return XCTFail("expected .unsupported")
        }
    }
}

extension ConversionJobFactory.Pipeline: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.ffmpeg, .ffmpeg), (.imageMagick, .imageMagick), (.ico, .ico), (.office, .office):
            return true
        case (.unsupported(let a), .unsupported(let b)):
            return a == b
        default:
            return false
        }
    }
}
