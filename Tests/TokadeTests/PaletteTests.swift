import AppKit
@testable import Tokade
import XCTest

final class PaletteTests: XCTestCase {
    func testRoleGlyphsAreDistinct() {
        let glyphs = Set(PaletteRole.allCases.map(\.glyph))
        XCTAssertEqual(glyphs.count, PaletteRole.allCases.count, "duplicate glyph in PaletteRole")
    }

    func testColorForTransparentGlyphIsNil() {
        XCTAssertNil(Palette.boba.color(forGlyph: "."))
    }

    func testColorForKnownGlyphResolves() {
        XCTAssertNotNil(Palette.boba.color(forGlyph: "2"))   // skin
        XCTAssertNotNil(Palette.boba.color(forGlyph: "5"))   // hair
        XCTAssertNotNil(Palette.boba.color(forGlyph: "9"))   // shirt
    }

    func testHexParsing() {
        guard let c = NSColor.fromHex("#A0B0C0")?.usingColorSpace(.sRGB) else {
            return XCTFail("hex parse failed")
        }
        XCTAssertEqual(c.redComponent,   0xA0 / 255, accuracy: 0.002)
        XCTAssertEqual(c.greenComponent, 0xB0 / 255, accuracy: 0.002)
        XCTAssertEqual(c.blueComponent,  0xC0 / 255, accuracy: 0.002)
    }

    func testHexParsingRejectsMalformed() {
        XCTAssertNil(NSColor.fromHex(""))
        XCTAssertNil(NSColor.fromHex("#xyzxyz"))
        XCTAssertNil(NSColor.fromHex("#FFF"))     // we require 6 digits
    }

    func testCharacterCreatorPresetsHaveExpectedCount() {
        XCTAssertEqual(CharacterCreatorSwatches.skin.count, 6)
        XCTAssertEqual(CharacterCreatorSwatches.iris.count, 6)
        XCTAssertEqual(CharacterCreatorSwatches.hair.count, 6)
        XCTAssertEqual(CharacterCreatorSwatches.hairStyles.count, 11)
    }
}
