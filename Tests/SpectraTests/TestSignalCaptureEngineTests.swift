#if canImport(XCTest)
import XCTest
@testable import SpectraCore

final class TestSignalCaptureEngineTests: XCTestCase {
    func testProducesBuffers() async throws {
        let engine = TestSignalCaptureEngine(signalType: .sine, sampleRate: 48_000, channelCount: 2, bufferSize: 128)
        let expectation = expectation(description: "buffer produced")
        expectation.assertForOverFulfill = false

        engine.setAudioBufferHandler { frame in
            XCTAssertEqual(frame.channelCount, 2)
            XCTAssertEqual(frame.frames, 128)
            XCTAssertEqual(frame.samples.count, 256)
            expectation.fulfill()
        }

        try await engine.start()
        await fulfillment(of: [expectation], timeout: 1.0)
        await engine.stop()
    }

    func testSupportsSineWave() async throws {
        let engine = TestSignalCaptureEngine(signalType: .sine, sampleRate: 48_000, channelCount: 1, bufferSize: 128)
        let expectation = expectation(description: "sine buffer")
        expectation.assertForOverFulfill = false

        engine.setAudioBufferHandler { frame in
            XCTAssertGreaterThan(frame.samples.map(abs).max() ?? 0, 0.1)
            expectation.fulfill()
        }

        try await engine.start()
        await fulfillment(of: [expectation], timeout: 1.0)
        await engine.stop()
    }

    func testSupportsBeatPulse() async throws {
        let engine = TestSignalCaptureEngine(signalType: .beatPattern, sampleRate: 48_000, channelCount: 1, bufferSize: 512)
        let expectation = expectation(description: "beat buffer")
        expectation.assertForOverFulfill = false

        engine.setAudioBufferHandler { frame in
            XCTAssertGreaterThan(frame.samples.map(abs).max() ?? 0, 0.05)
            expectation.fulfill()
        }

        try await engine.start()
        await fulfillment(of: [expectation], timeout: 1.0)
        await engine.stop()
    }

    func testStartStopWorks() async throws {
        let engine = TestSignalCaptureEngine()

        try await engine.start()
        XCTAssertTrue(engine.isRunning)
        await engine.stop()
        XCTAssertFalse(engine.isRunning)
    }
}
#endif
