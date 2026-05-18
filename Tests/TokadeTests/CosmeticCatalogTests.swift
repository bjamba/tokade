@testable import Tokade
import XCTest

/// Guard tests against drift between the character creator's hair carousel
/// and the wardrobe catalog. v0.4.1 shipped with four hair styles
/// (bald / flame / mushroom / tentacles) that were selectable at hatch but
/// missing from the wardrobe — a silent UX bug because the sprites baked
/// and rendered fine, the catalog just didn't list them.
final class CosmeticCatalogTests: XCTestCase {
    /// Every style the character creator offers must also appear in the
    /// CosmeticCatalog hair slot. Failure mode this guards against: someone
    /// adds a new hair style for hatch but forgets to register it as a
    /// wardrobe entry.
    func testEveryHatchHairStyleIsInTheCosmeticCatalog() {
        let catalog = Set(CosmeticCatalog.bySlot("hair").map(\.id))
        let creator = Set(CharacterCreatorSwatches.hairStyles)
        let missing = creator.subtracting(catalog)
        XCTAssertTrue(
            missing.isEmpty,
            "Hair styles in CharacterCreatorSwatches.hairStyles but not in "
                + "CosmeticCatalog: \(missing.sorted())"
        )
    }

    /// Reverse drift check: every hair cosmetic in the catalog should be a
    /// known hatch style. If a wardrobe-only hair ever ships, the
    /// character creator and the cosmetic catalog will silently disagree.
    func testEveryCatalogHairStyleIsAHatchOption() {
        let catalog = Set(CosmeticCatalog.bySlot("hair").map(\.id))
        let creator = Set(CharacterCreatorSwatches.hairStyles)
        let orphans = catalog.subtracting(creator)
        XCTAssertTrue(
            orphans.isEmpty,
            "Hair cosmetics in CosmeticCatalog but not in "
                + "CharacterCreatorSwatches.hairStyles: \(orphans.sorted())"
        )
    }
}
