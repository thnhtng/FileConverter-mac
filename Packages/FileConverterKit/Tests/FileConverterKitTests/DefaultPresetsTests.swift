import XCTest
@testable import FileConverterKit

final class DefaultPresetsTests: XCTestCase {
    func testBuiltInPresetSetCoversEveryOutputType() {
        let presets = DefaultPresets.builtInPresetSet()
        XCTAssertEqual(Set(presets.map(\.outputType)), Set(OutputType.allCases))
    }

    func testMp4DefaultsMatchWindowsApp() {
        guard case .video(let s) = DefaultPresets.defaultSettings(for: .mp4) else { return XCTFail() }
        XCTAssertEqual(s.quality, 28)
        XCTAssertEqual(s.encodingSpeed, .medium)
        XCTAssertEqual(s.audioBitrateKbps, 128)
        XCTAssertTrue(s.enableAudio)
    }

    func testIcoDefaultsClampToPowerOfTwoAt256() {
        guard case .image(let s) = DefaultPresets.defaultSettings(for: .ico) else { return XCTFail() }
        XCTAssertTrue(s.clampSizeToPowerOfTwo)
        XCTAssertEqual(s.maximumSizePixels, 256)
    }

    func testPresetInputTypesAreCompatibleWithOutputType() {
        for preset in DefaultPresets.builtInPresetSet() {
            for inputType in preset.inputTypes {
                let category = InputCategoryClassifier.category(forExtension: inputType)
                XCTAssertTrue(
                    InputCategoryClassifier.isOutputType(preset.outputType, compatibleWith: category),
                    "\(inputType) (\(category)) should be compatible with \(preset.outputType)"
                )
            }
        }
    }

    func testShortNameAndParentFolders() {
        let preset = ConversionPreset(
            fullName: "Scale 75%/To Mkv",
            outputType: .mkv,
            inputTypes: ["mov"],
            settings: DefaultPresets.defaultSettings(for: .mkv)
        )
        XCTAssertEqual(preset.shortName, "To Mkv")
        XCTAssertEqual(preset.parentFolderNames, ["Scale 75%"])
    }
}
