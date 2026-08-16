import XCTest
@testable import FileConverterKit

final class FileConverterKitTests: XCTestCase {
    func testSchemaVersionIsPositive() {
        XCTAssertGreaterThan(FileConverterKit.settingsSchemaVersion, 0)
    }
}
