import XCTest

/// Layer-3 XCUITest smoke (ci-l3-apple-xcuitest).
///
/// Industry-standard Apple UI test. Launches Wawona and asserts Machines (or
/// Welcome) accessibility wiring. Gate: products prefers simctl install of the
/// product .app; this suite is for `xcodebuild test` / local.
final class WawonaUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMachinesUiPresentOnLaunch() throws {
        let app = XCUIApplication(bundleIdentifier: "com.aspauldingcode.Wawona")
        app.launch()

        let welcome = app.otherElements["wwn.welcome.root"]
        let machines = app.otherElements["wwn.machines.root"]
        let welcomeContinue = app.buttons["wwn.welcome.continue"]

        let sawWelcome = welcome.waitForExistence(timeout: 12)
        if sawWelcome, welcomeContinue.waitForExistence(timeout: 5) {
            welcomeContinue.tap()
        }

        XCTAssertTrue(
            machines.waitForExistence(timeout: 20),
            "Machines root (wwn.machines.root) did not appear after launch"
        )
    }
}
