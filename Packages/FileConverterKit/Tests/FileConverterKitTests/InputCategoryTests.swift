import XCTest
@testable import FileConverterKit

final class InputCategoryTests: XCTestCase {
    func testCategoryClassification() {
        XCTAssertEqual(InputCategoryClassifier.category(forExtension: "mp3"), .audio)
        XCTAssertEqual(InputCategoryClassifier.category(forExtension: "MP4"), .video)
        XCTAssertEqual(InputCategoryClassifier.category(forExtension: "png"), .image)
        XCTAssertEqual(InputCategoryClassifier.category(forExtension: "gif"), .animatedImage)
        XCTAssertEqual(InputCategoryClassifier.category(forExtension: "docx"), .document)
        XCTAssertEqual(InputCategoryClassifier.category(forExtension: "xyz"), .misc)
    }

    func testMiscIsAlwaysCompatible() {
        XCTAssertTrue(InputCategoryClassifier.isOutputType(.mp3, compatibleWith: .misc))
        XCTAssertTrue(InputCategoryClassifier.isOutputType(.pdf, compatibleWith: .misc))
    }

    func testAudioOutputsAcceptAudioAndVideoOnly() {
        for outputType: OutputType in [.aac, .flac, .mp3, .ogg, .wav] {
            XCTAssertTrue(InputCategoryClassifier.isOutputType(outputType, compatibleWith: .audio))
            XCTAssertTrue(InputCategoryClassifier.isOutputType(outputType, compatibleWith: .video))
            XCTAssertFalse(InputCategoryClassifier.isOutputType(outputType, compatibleWith: .image))
            XCTAssertFalse(InputCategoryClassifier.isOutputType(outputType, compatibleWith: .document))
        }
    }

    func testGifAcceptsImageVideoAndAnimatedImage() {
        XCTAssertTrue(InputCategoryClassifier.isOutputType(.gif, compatibleWith: .image))
        XCTAssertTrue(InputCategoryClassifier.isOutputType(.gif, compatibleWith: .video))
        XCTAssertTrue(InputCategoryClassifier.isOutputType(.gif, compatibleWith: .animatedImage))
        XCTAssertFalse(InputCategoryClassifier.isOutputType(.gif, compatibleWith: .audio))
    }

    func testPdfAcceptsImageAndDocumentOnly() {
        XCTAssertTrue(InputCategoryClassifier.isOutputType(.pdf, compatibleWith: .image))
        XCTAssertTrue(InputCategoryClassifier.isOutputType(.pdf, compatibleWith: .document))
        XCTAssertFalse(InputCategoryClassifier.isOutputType(.pdf, compatibleWith: .video))
        XCTAssertFalse(InputCategoryClassifier.isOutputType(.pdf, compatibleWith: .animatedImage))
    }

    func testCompatibleInputExtensionsForMp4IncludesVideoAndAnimatedImage() {
        let exts = Set(InputCategoryClassifier.compatibleInputExtensions(for: .mp4))
        XCTAssertTrue(exts.contains("mov"))
        XCTAssertTrue(exts.contains("gif"))
        XCTAssertFalse(exts.contains("mp3"))
    }
}
