#if canImport(XCTest)
import XCTest
@testable import SpectraCore

final class SettingsStoreTests: XCTestCase {
    func testSettingsPersistToCustomURL() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spectra-settings-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SettingsStore(url: url)
        var settings = UserSettings.default
        settings.selectedPreset = .neonTunnel
        settings.captureMode = .systemMix
        settings.presetSettings.sensitivity = 0.37
        settings.showDebugOverlay = true

        store.save(settings)
        let loaded = store.load()

        XCTAssertEqual(loaded.selectedPreset, .neonTunnel)
        XCTAssertEqual(loaded.captureMode, .systemMix)
        XCTAssertEqual(loaded.presetSettings.sensitivity, 0.37, accuracy: 0.0001)
        XCTAssertTrue(loaded.showDebugOverlay)
    }

    func testInvalidSettingsFileFallsBackToDefault() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spectra-settings-invalid-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)

        let loaded = SettingsStore(url: url).load()

        XCTAssertEqual(loaded, .default)
    }
}
#endif
