import XCTest
@testable import UnraidPilot

final class UnraidPilotTests: XCTestCase {
    func testPreviewCapacityIsValid() {
        XCTAssertGreaterThan(ServerSnapshot.preview.arrayTotalTB, ServerSnapshot.preview.arrayUsedTB)
        XCTAssertEqual(ServerSnapshot.preview.disks.filter { $0.status == .warning }.count, 1)
    }
}

