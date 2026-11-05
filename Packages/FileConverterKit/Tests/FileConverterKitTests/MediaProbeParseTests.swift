import XCTest
@testable import FileConverterKit

final class MediaProbeParseTests: XCTestCase {
    private func parse(_ json: String, name: String) throws -> MediaInfo {
        try MediaProbe.parse(ffprobeJSON: Data(json.utf8), fileURL: URL(fileURLWithPath: "/tmp/\(name)"), fileSizeBytes: 1234)
    }

    func testPhoneVideoWithDisplayMatrixRotation() throws {
        let info = try parse("""
        {"streams":[
          {"codec_type":"video","codec_name":"hevc","width":1920,"height":1080,"avg_frame_rate":"30000/1001",
           "side_data_list":[{"side_data_type":"Display Matrix","rotation":-90}]},
          {"codec_type":"audio","codec_name":"aac"}],
         "format":{"format_name":"mov,mp4,m4a,3gp,3g2,mj2","duration":"12.512","bit_rate":"8123456"}}
        """, name: "IMG_0001.MOV")
        XCTAssertEqual(info.kind, .video)
        XCTAssertEqual(info.rotationDegrees, 270)
        XCTAssertEqual(info.displayWidth, 1080)
        XCTAssertEqual(info.displayHeight, 1920)
        XCTAssertEqual(info.durationSeconds ?? 0, 12.512, accuracy: 0.0001)
        XCTAssertEqual(info.framesPerSecond ?? 0, 29.97, accuracy: 0.01)
        XCTAssertEqual(info.videoCodec, "hevc")
        XCTAssertEqual(info.audioCodec, "aac")
        XCTAssertTrue(info.hasAudio)
        XCTAssertEqual(info.bitrateKbps, 8123)
        XCTAssertEqual(info.fileSizeBytes, 1234)
    }

    func testLegacyRotateTag() throws {
        let info = try parse("""
        {"streams":[{"codec_type":"video","codec_name":"h264","width":1280,"height":720,"r_frame_rate":"25/1","tags":{"rotate":"90"}}],
         "format":{"duration":"3.0"}}
        """, name: "old.mp4")
        XCTAssertEqual(info.rotationDegrees, 90)
        XCTAssertEqual(info.framesPerSecond, 25)
        XCTAssertFalse(info.hasAudio)
    }

    func testMp3CoverArtIsNotAVideoStream() throws {
        let info = try parse("""
        {"streams":[{"codec_type":"audio","codec_name":"mp3"},
                    {"codec_type":"video","codec_name":"mjpeg","width":600,"height":600,"disposition":{"attached_pic":1}}],
         "format":{"format_name":"mp3","duration":"200.1"}}
        """, name: "song.mp3")
        XCTAssertEqual(info.kind, .audio)
        XCTAssertNil(info.width)
        XCTAssertNil(info.videoCodec)
        XCTAssertEqual(info.audioCodec, "mp3")
    }

    func testStillImage() throws {
        let info = try parse("""
        {"streams":[{"codec_type":"video","codec_name":"png","width":1290,"height":2796,"avg_frame_rate":"0/0"}],
         "format":{"format_name":"png_pipe"}}
        """, name: "shot.png")
        XCTAssertEqual(info.kind, .image)
        XCTAssertEqual(info.width, 1290)
        XCTAssertNil(info.durationSeconds)
        XCTAssertNil(info.framesPerSecond)
        XCTAssertNil(info.videoCodec)
    }

    func testGarbageThrows() {
        XCTAssertThrowsError(try parse("not json", name: "x.mp4"))
    }

    func testFrameRateAndIdentifyHelpers() {
        XCTAssertNil(MediaProbe.frameRate("0/0"))
        XCTAssertNil(MediaProbe.frameRate(nil))
        XCTAssertEqual(MediaProbe.frameRate("60/1"), 60)
        XCTAssertEqual(MediaProbe.parseIdentify("1290 2796\n")?.width, 1290)
        XCTAssertNil(MediaProbe.parseIdentify("garbage"))
    }
}
