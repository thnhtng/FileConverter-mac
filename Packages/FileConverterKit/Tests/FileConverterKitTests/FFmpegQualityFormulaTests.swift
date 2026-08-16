import XCTest
@testable import FileConverterKit

final class FFmpegQualityFormulaTests: XCTestCase {
    func testH264CRF() {
        XCTAssertEqual(FFmpegQualityFormulas.h264CRF(quality: 28), 23) // Mp4/Mkv default
        XCTAssertEqual(FFmpegQualityFormulas.h264CRF(quality: 0), 51)
        XCTAssertEqual(FFmpegQualityFormulas.h264CRF(quality: 51), 0)
    }

    func testWebmCRF() {
        XCTAssertEqual(FFmpegQualityFormulas.webmCRF(quality: 40), 23) // Webm default
        XCTAssertEqual(FFmpegQualityFormulas.webmCRF(quality: 63), 0)
    }

    func testMpeg4QualityIndex() {
        XCTAssertEqual(FFmpegQualityFormulas.mpeg4QualityIndex(quality: 20), 11) // Avi default
    }

    func testJpgQualityIndex() {
        XCTAssertEqual(FFmpegQualityFormulas.jpgQualityIndex(quality: 1), 30)
    }

    func testMp3VBRTable() {
        XCTAssertEqual(FFmpegQualityFormulas.mp3VBRQualityIndex(bitrateKbps: 190), 2) // Mp3 default
        XCTAssertEqual(FFmpegQualityFormulas.mp3VBRQualityIndex(bitrateKbps: 65), 9)
        XCTAssertNil(FFmpegQualityFormulas.mp3VBRQualityIndex(bitrateKbps: 999))
    }

    func testOggVBRTable() {
        XCTAssertEqual(FFmpegQualityFormulas.oggVBRQualityIndex(bitrateKbps: 160), 5) // Ogg default
        XCTAssertEqual(FFmpegQualityFormulas.oggVBRQualityIndex(bitrateKbps: 32), -2)
        XCTAssertNil(FFmpegQualityFormulas.oggVBRQualityIndex(bitrateKbps: 999))
    }

    func testAACTable() {
        XCTAssertEqual(FFmpegQualityFormulas.aacQualityIndex(bitrateKbps: 128), "1") // Aac/Mkv/Mp4 default
        XCTAssertEqual(FFmpegQualityFormulas.aacQualityIndex(bitrateKbps: 16), "0.1")
        XCTAssertNil(FFmpegQualityFormulas.aacQualityIndex(bitrateKbps: 999))
    }

    func testWavCodecArgument() {
        XCTAssertEqual(FFmpegQualityFormulas.wavCodecArgument(.wav16), "pcm_s16le")
        XCTAssertEqual(FFmpegQualityFormulas.wavCodecArgument(.wav8), "pcm_s8le")
        XCTAssertEqual(FFmpegQualityFormulas.wavCodecArgument(.wav24), "pcm_s24le")
        XCTAssertEqual(FFmpegQualityFormulas.wavCodecArgument(.wav32), "pcm_s32le")
    }
}
