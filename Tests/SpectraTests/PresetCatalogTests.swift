#if canImport(XCTest)
import XCTest
@testable import SpectraCore

final class PresetCatalogTests: XCTestCase {
    func testCatalogContainsEveryPresetIdExactlyOnce() {
        let ids = PresetCatalog.presets.map(\.id)

        XCTAssertEqual(Set(ids), Set(VisualPresetID.allCases))
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testDefaultSettingsStayInExpectedRanges() {
        for preset in PresetCatalog.presets {
            XCTAssert((0...1).contains(preset.defaultSettings.intensity), "\(preset.name) intensity out of range")
            XCTAssert((0...1).contains(preset.defaultSettings.sensitivity), "\(preset.name) sensitivity out of range")
            XCTAssert((0...1).contains(preset.defaultSettings.motionAmount), "\(preset.name) motion out of range")
            XCTAssert((0...1).contains(preset.defaultSettings.glowAmount), "\(preset.name) glow out of range")
        }
    }

    func testFractalPresetsMapToUniqueShaderModes() {
        let fractalPresets = PresetCatalog.presets.filter { $0.category == .fractal }
        let modes = fractalPresets.compactMap { $0.id.fractalMode }

        XCTAssertEqual(fractalPresets.count, 5)
        XCTAssertEqual(modes.count, fractalPresets.count)
        XCTAssertEqual(Set(modes), Set(0...4))
    }
}
#endif
