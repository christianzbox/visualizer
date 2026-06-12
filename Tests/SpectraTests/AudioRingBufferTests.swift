#if canImport(XCTest)
import XCTest
@testable import SpectraCore

final class AudioRingBufferTests: XCTestCase {
    func testKeepsMostRecentSamplesWhenCapacityIsExceeded() {
        let buffer = AudioRingBuffer(capacity: 5)

        buffer.append([1, 2, 3])
        buffer.append([4, 5, 6, 7])

        XCTAssertEqual(buffer.latest(5), [3, 4, 5, 6, 7])
        XCTAssertEqual(buffer.latest(3), [5, 6, 7])
    }

    func testClearRemovesBufferedSamples() {
        let buffer = AudioRingBuffer(capacity: 4)

        buffer.append([1, 2, 3, 4])
        buffer.clear()

        XCTAssertEqual(buffer.latest(4), [])
    }
}
#endif
