import XCTest

/// Layer-3 XCUITest smoke (ci-l3-apple-xcuitest).
///
/// Launches the Wawona app and asserts the compositor surface is present via its
/// stable accessibility identifier (`wwn.compositor.surface`, set in
/// `WWNCompositorView_ios`). This is the fast "app boots and wires up its UI"
/// gate; pixel-level compositor correctness is covered by agent-device replays.
final class WawonaUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCompositorSurfacePresentOnLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // The compositor view exposes accessibilityIdentifier "wwn.compositor.surface".
        let surface = app.otherElements["wwn.compositor.surface"]
        XCTAssertTrue(
            surface.waitForExistence(timeout: 10),
            "compositor surface did not appear within 10s of launch"
        )
    }
}
