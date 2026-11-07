import XCTest
@testable import FileConverterKit

final class SpecCodingAndImportTests: XCTestCase {
    func testSpecRoundTrips() throws {
        let data = try JSONEncoder().encode(DefaultSpecs.all)
        XCTAssertEqual(try JSONDecoder().decode([DeliverySpec].self, from: data), DefaultSpecs.all)
    }

    func testLenientDecodeFillsDefaultsAndNormalizes() throws {
        let spec = try JSONDecoder().decode(DeliverySpec.self, from: Data("""
        {"name":"Partner","allowedExtensions":[".MP4","JPEG"],"width":null,"allowedVideoCodecs":["H264"]}
        """.utf8))
        XCTAssertEqual(spec.name, "Partner")
        XCTAssertEqual(spec.allowedExtensions, ["mp4", "jpg"])
        XCTAssertEqual(spec.allowedVideoCodecs, ["h264"])
        XCTAssertNil(spec.width)
        XCTAssertEqual(spec.audio, .optional)
        XCTAssertEqual(spec.aspectRatioTolerance, 0.01)
        XCTAssertEqual(spec.mediaKinds, [])
    }

    func testSettingsWrittenBeforeSpecCheckStillLoad() throws {
        // Encode current settings, strip the new key -> simulates an older file.
        let current = AppSettings(presets: [DefaultPresets.preset(for: .mp3)])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(current)) as? [String: Any])
        object.removeValue(forKey: "deliverySpecs")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let loaded = try JSONDecoder().decode(AppSettings.self, from: legacy)
        XCTAssertEqual(loaded.deliverySpecs, DefaultSpecs.all)
        XCTAssertEqual(loaded.presets.count, 1)
    }

    func testPresetWithoutFixFieldsDecodes() throws {
        // A VideoSettings JSON from before the fix fields existed.
        let video = try JSONDecoder().decode(VideoSettings.self, from: Data("""
        {"quality":28,"encodingSpeed":"medium","scale":1,"rotationDegrees":0,"enableAudio":true,"audioBitrateKbps":128}
        """.utf8))
        XCTAssertNil(video.frameTarget)
        XCTAssertNil(video.maxVideoBitrateKbps)
    }

    func testEditsAreNormalizedToo() {
        var spec = DeliverySpec(name: "x")
        spec.allowedExtensions = [".JPEG", "PNG"]
        spec.allowedVideoCodecs = ["H264"]
        XCTAssertEqual(spec.allowedExtensions, ["jpg", "png"])
        XCTAssertEqual(spec.allowedVideoCodecs, ["h264"])
    }

    func testAspectRatioParsing() {
        XCTAssertEqual(AspectRatio(string: "9:16"), .vertical9x16)
        XCTAssertEqual(AspectRatio(string: "16x9"), .landscape16x9)
        XCTAssertNil(AspectRatio(string: "wide"))
        XCTAssertNil(AspectRatio(string: "0:1"))
    }

    // MARK: Claude importer

    func testImporterRequestShape() throws {
        let request = try ClaudeSpecImporter(apiKey: " sk-test \n").makeURLRequest(text: "  Max 30MB, 9:16  ")
        XCTAssertEqual(request.url, ClaudeSpecImporter.endpoint)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2026-10-21")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01")

        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "claude-opus-5-5")
        XCTAssertEqual(body["fallbacks"] as? String, "default")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue((messages[0]["content"] as? String)?.hasSuffix("Max 30MB, 9:16") == true)

        let outputConfig = try XCTUnwrap(body["output_config"] as? [String: Any])
        let format = try XCTUnwrap(outputConfig["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertEqual(Set(schema["required"] as? [String] ?? []), Set(properties.keys))
    }

    func testImporterRejectsMissingKeyAndEmptyText() {
        XCTAssertThrowsError(try ClaudeSpecImporter(apiKey: "").makeURLRequest(text: "x")) {
            XCTAssertEqual($0 as? SpecImportError, .missingAPIKey)
        }
        XCTAssertThrowsError(try ClaudeSpecImporter(apiKey: "k").makeURLRequest(text: "   ")) {
            XCTAssertEqual($0 as? SpecImportError, .emptyInput)
        }
    }

    func testParsesStructuredResponseSkippingThinkingBlocks() throws {
        let specJSON = #"{"name":"Vertical ad","notes":"Also accepts 4:5.","mediaKinds":["video"],"allowedExtensions":["MP4"],"maxFileSizeMB":30,"width":1080,"height":1920,"minWidth":null,"minHeight":null,"maxWidth":null,"maxHeight":null,"aspectRatios":[{"width":9,"height":16}],"minDurationSeconds":5,"maxDurationSeconds":60,"minFramesPerSecond":null,"maxFramesPerSecond":null,"allowedVideoCodecs":["H264"],"allowedAudioCodecs":null,"audio":"required"}"#
        let envelope: [String: Any] = [
            "id": "msg_1", "type": "message", "role": "assistant", "stop_reason": "end_turn",
            "content": [["type": "thinking", "thinking": ""], ["type": "text", "text": specJSON]]
        ]
        let spec = try ClaudeSpecImporter.parseResponse(JSONSerialization.data(withJSONObject: envelope))
        XCTAssertEqual(spec.name, "Vertical ad")
        XCTAssertEqual(spec.allowedExtensions, ["mp4"])
        XCTAssertEqual(spec.allowedVideoCodecs, ["h264"])
        XCTAssertEqual(spec.aspectRatios, [.vertical9x16])
        XCTAssertEqual(spec.audio, .required)
        XCTAssertEqual(spec.maxFileSizeMB, 30)
        XCTAssertFalse(spec.isBuiltIn)
    }

    func testParsesRefusalAndErrors() throws {
        let refusal = try JSONSerialization.data(withJSONObject: ["stop_reason": "refusal", "content": []] as [String: Any])
        XCTAssertThrowsError(try ClaudeSpecImporter.parseResponse(refusal)) { XCTAssertEqual($0 as? SpecImportError, .refused) }
        let cut = try JSONSerialization.data(withJSONObject: ["stop_reason": "max_tokens", "content": []] as [String: Any])
        XCTAssertThrowsError(try ClaudeSpecImporter.parseResponse(cut)) { XCTAssertEqual($0 as? SpecImportError, .truncated) }
        XCTAssertEqual(
            ClaudeSpecImporter.errorMessage(from: Data(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8)),
            "invalid x-api-key"
        )
    }

    // MARK: Reports

    func testCSVEscapesAndListsEveryFinding() {
        let info = MediaInfo(fileURL: URL(fileURLWithPath: "/tmp/a, \"b\".mp4"), fileSizeBytes: 40_000_000, kind: .video,
                             width: 1920, height: 1080, durationSeconds: 10, framesPerSecond: 30, videoCodec: "h264", audioCodec: "aac", hasAudio: true)
        let result = SpecChecker.check(info, against: DefaultSpecs.verticalVideoAd)
        let csv = SpecCheckReport.csv([result])
        let lines = csv.split(separator: "\r\n")
        XCTAssertEqual(lines.count, 1 + result.findings.count)
        XCTAssertTrue(lines[1].hasPrefix("\"a, \"\"b\"\".mp4\",Vertical video ad (9:16),Fail,"), String(lines[1]))
    }

    func testHTMLEscapesFileNames() {
        let info = MediaInfo(fileURL: URL(fileURLWithPath: "/tmp/<script>.png"), fileSizeBytes: 1, kind: .image, width: 1, height: 1)
        let html = SpecCheckReport.html([SpecChecker.check(info, against: DefaultSpecs.chatAttachment)])
        XCTAssertTrue(html.contains("&lt;script&gt;.png"))
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("1 pass"))
    }
}
