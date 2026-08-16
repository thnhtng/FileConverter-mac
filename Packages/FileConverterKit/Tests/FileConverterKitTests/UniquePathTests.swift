import XCTest
@testable import FileConverterKit

final class UniquePathTests: XCTestCase {
    func testReturnsSamePathWhenFree() {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        XCTAssertEqual(UniquePath.generate(base: base), base)
    }

    func testAppendsIndexWhenPathExists() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let base = dir.appendingPathComponent("file.txt")
        try Data().write(to: base)

        let unique = UniquePath.generate(base: base)
        XCTAssertEqual(unique.lastPathComponent, "file (1).txt")
    }
}

final class SettingsStoreTests: XCTestCase {
    func testRoundTripsThroughJSON() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }

        let original = try SettingsStore.loadOrSeed(url: url)
        XCTAssertEqual(original.presets.count, OutputType.allCases.count)

        let reloaded = try SettingsStore.loadOrSeed(url: url)
        XCTAssertEqual(original, reloaded)
    }
}
