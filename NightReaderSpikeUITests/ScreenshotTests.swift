import XCTest

final class ScreenshotTests: XCTestCase {

    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = true
        app.launch()
        // Wait for PDF to load
        sleep(2)
    }

    func testCaptureAllCombinations() throws {
        let pdfNames = ["Text Only", "Text + Images", "Colored Diagrams"]
        let modeNames = ["Off", "Simple", "Smart"]

        for pdfName in pdfNames {
            // Tap the PDF picker segment
            let pdfButton = app.buttons[pdfName]
            if pdfButton.waitForExistence(timeout: 3) {
                pdfButton.tap()
                sleep(1)
            }

            for modeName in modeNames {
                // Tap the dark mode picker segment
                let modeButton = app.buttons[modeName]
                if modeButton.waitForExistence(timeout: 3) {
                    modeButton.tap()
                    sleep(2) // Wait for rendering
                }

                let screenshotName = "\(pdfName.replacingOccurrences(of: " ", with: "_"))__\(modeName)"
                let screenshot = app.screenshot()
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = screenshotName
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
}
