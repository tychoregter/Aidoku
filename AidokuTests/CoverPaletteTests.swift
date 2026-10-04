import UIKit
import XCTest
@testable import Aidoku

@MainActor
final class CoverPaletteTests: XCTestCase {
    private func image(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
    }

    func testLoadedCoverPreparesBothAppearancesAndReplacesChangedArtwork() async {
        let url = "https://example.com/cover-palette-test.png"
        CoverPalette.invalidate(url: url)
        let redReady = expectation(description: "Red cover sampled")
        CoverPalette.observe(image(.red), for: url) { color in
            if color.redComponent > 0.8 { redReady.fulfill() }
        }
        await fulfillment(of: [redReady], timeout: 3)

        XCTAssertNotNil(CoverPalette.headerColor(for: url, dark: false))
        XCTAssertNotNil(CoverPalette.headerColor(for: url, dark: true))
        XCTAssertNotNil(CoverPalette.hiddenColor(for: url, dark: false))
        XCTAssertNotNil(CoverPalette.hiddenColor(for: url, dark: true))
        XCTAssertNotNil(CoverPalette.controlColor(for: url, dark: true))

        let blueReady = expectation(description: "Changed artwork sampled under the same URL")
        CoverPalette.observe(image(.blue), for: url) { color in
            if color.blueComponent > 0.8 { blueReady.fulfill() }
        }
        await fulfillment(of: [blueReady], timeout: 3)
        XCTAssertGreaterThan(CoverPalette.color(for: url)?.blueComponent ?? 0, 0.8)

        CoverPalette.invalidate(url: url)
        XCTAssertNil(CoverPalette.color(for: url))
    }
}

private extension UIColor {
    var redComponent: CGFloat {
        var red: CGFloat = 0
        getRed(&red, green: nil, blue: nil, alpha: nil)
        return red
    }

    var blueComponent: CGFloat {
        var blue: CGFloat = 0
        getRed(nil, green: nil, blue: &blue, alpha: nil)
        return blue
    }
}
