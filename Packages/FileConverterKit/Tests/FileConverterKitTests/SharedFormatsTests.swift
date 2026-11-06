import XCTest
@testable import FileConverterKit

/// `shared/formats.json` drives the web converter, the browser extension and
/// the Windows right-click menu. These tests keep it in lockstep with the
/// Swift engine, so a file converts to the same formats — with the same
/// quality defaults — wherever it's converted.
final class SharedFormatsTests: XCTestCase {
    private struct SharedFormats: Decodable {
        struct Output: Decodable {
            var label: String
            var accepts: [String]
            var ffmpeg: [String]?
            var image: Image?
            var gif: Gif?
            var web: Bool?
        }
        struct Image: Decodable { var quality: Int; var maxSize: Int?; var densityDpi: Int? }
        struct Gif: Decodable { var fps: Int }
        var categories: [String: [String]]
        var outputs: [String: Output]
    }

    private func load() throws -> SharedFormats {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // FileConverterKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // FileConverterKit
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("shared/formats.json")
        return try JSONDecoder().decode(SharedFormats.self, from: Data(contentsOf: url))
    }

    private func category(named name: String) -> InputCategory? {
        switch name {
        case "audio": return .audio
        case "video": return .video
        case "image": return .image
        case "animatedImage": return .animatedImage
        case "document": return .document
        default: return nil
        }
    }

    func testCategoriesMatchClassifier() throws {
        let formats = try load()
        var all = Set<String>()
        for (name, extensions) in formats.categories {
            let expected = try XCTUnwrap(category(named: name), "unknown category \(name)")
            for ext in extensions {
                XCTAssertEqual(InputCategoryClassifier.category(forExtension: ext), expected, ext)
                all.insert(ext)
            }
        }
        XCTAssertEqual(all, InputCategoryClassifier.compatibleInputExtensions)
    }

    func testEveryOutputTypeIsListedWithTheSameCompatibility() throws {
        let formats = try load()
        XCTAssertEqual(Set(formats.outputs.keys), Set(OutputType.allCases.map(\.rawValue)))
        for type in OutputType.allCases {
            let output = try XCTUnwrap(formats.outputs[type.rawValue])
            for name in ["audio", "video", "image", "animatedImage", "document"] {
                let cat = try XCTUnwrap(category(named: name))
                XCTAssertEqual(
                    output.accepts.contains(name),
                    InputCategoryClassifier.isOutputType(type, compatibleWith: cat),
                    "\(type.rawValue) accepting \(name)"
                )
            }
        }
    }

    func testQualityDefaultsMatchDefaultPresets() throws {
        let formats = try load()
        func value(_ flag: String, in type: OutputType) throws -> String? {
            let args = try XCTUnwrap(formats.outputs[type.rawValue]?.ffmpeg)
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        for type in [OutputType.mp4, .mkv] {
            let q = try XCTUnwrap(DefaultPresets.defaultSettings(for: type).video?.quality)
            XCTAssertEqual(try value("-crf", in: type), "\(FFmpegQualityFormulas.h264CRF(quality: q))")
        }
        let webmQ = try XCTUnwrap(DefaultPresets.defaultSettings(for: .webm).video?.quality)
        XCTAssertEqual(try value("-crf", in: .webm), "\(FFmpegQualityFormulas.webmCRF(quality: webmQ))")
        let aviQ = try XCTUnwrap(DefaultPresets.defaultSettings(for: .avi).video?.quality)
        XCTAssertEqual(try value("-qscale:v", in: .avi), "\(FFmpegQualityFormulas.mpeg4QualityIndex(quality: aviQ))")
        let ogvQ = try XCTUnwrap(DefaultPresets.defaultSettings(for: .ogv).video?.quality)
        XCTAssertEqual(try value("-qscale:v", in: .ogv), "\(FFmpegQualityFormulas.theoraQualityIndex(quality: ogvQ))")
        let mp3 = try XCTUnwrap(DefaultPresets.defaultSettings(for: .mp3).audio)
        XCTAssertEqual(try value("-q:a", in: .mp3), FFmpegQualityFormulas.mp3VBRQualityIndex(bitrateKbps: mp3.bitrateKbps).map(String.init))
        let ogg = try XCTUnwrap(DefaultPresets.defaultSettings(for: .ogg).audio)
        XCTAssertEqual(try value("-q:a", in: .ogg), FFmpegQualityFormulas.oggVBRQualityIndex(bitrateKbps: ogg.bitrateKbps).map(String.init))
        XCTAssertEqual(try value("-b:a", in: .aac), "\(DefaultPresets.defaultSettings(for: .aac).audio?.bitrateKbps ?? 0)k")

        for type in [OutputType.jpg, .png, .webp, .avif, .ico] {
            XCTAssertEqual(formats.outputs[type.rawValue]?.image?.quality, DefaultPresets.defaultSettings(for: type).image?.quality, type.rawValue)
        }
        XCTAssertEqual(formats.outputs["ico"]?.image?.maxSize, DefaultPresets.defaultSettings(for: .ico).image?.maximumSizePixels)
        XCTAssertEqual(formats.outputs["pdf"]?.image?.densityDpi, DefaultPresets.defaultSettings(for: .pdf).document?.densityDpi)
        XCTAssertEqual(formats.outputs["gif"]?.gif?.fps, DefaultPresets.defaultSettings(for: .gif).gifSettings?.framesPerSecond)
    }
}
