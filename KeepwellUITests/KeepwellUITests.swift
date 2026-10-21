import XCTest

/// End-to-end checks that need the real iOS system UI (permission and delete alerts).
/// Run by .github/workflows/sim-proof.yml after the screenshot hooks, against the seeded Simulator library.
/// Screenshots are attached to the result and, when TEST_RUNNER_KW_UI_SHOTS is set, written there as PNGs.
@MainActor
final class KeepwellUITests: XCTestCase {

    // MARK: Helpers

    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["KW_UI_SHOTS"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    /// Taps the first button with one of `labels` in a system alert (springboard), then in the app.
    @discardableResult
    private func tapSystemButton(_ labels: [String], app: XCUIApplication, timeout: TimeInterval = 15) -> String? {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let sources = [springboard, app] + Self.systemUIBundles.map { XCUIApplication(bundleIdentifier: $0) }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for (i, source) in sources.enumerated() {
                for label in labels {
                    let button = source.alerts.buttons[label]
                    if button.exists { button.tap(); return label }
                    if i != 1 {  // outside the app, any hittable button with that label is the system one
                        let any = source.buttons[label]
                        if any.exists, any.isHittable { any.tap(); return label }
                    }
                }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        // Diagnostics: what was on screen and in the accessibility trees.
        shot("diag-\(labels.first ?? "alert")")
        for (i, source) in sources.prefix(2).enumerated() {
            let a = XCTAttachment(string: source.debugDescription)
            a.name = "tree-\(i)"; a.lifetime = .keepAlways; add(a)
            if let dir = ProcessInfo.processInfo.environment["KW_UI_SHOTS"] {
                try? source.debugDescription.write(toFile: dir + "/tree-\(i).txt", atomically: true, encoding: .utf8)
            }
        }
        return nil
    }

    private static let systemUIBundles = ["com.apple.PhotosViewService", "com.apple.mobileslideshow", "com.apple.photos.service"]

    private func leadingInt(_ s: String) -> Int? {
        Int(s.prefix(while: { $0.isNumber }))
    }

    // MARK: Tests

    /// Denied access: the workflow runs `simctl privacy revoke photos` first. On the iOS 26 runtime that can
    /// read back as "not determined", so the test then denies through the real system alert instead.
    func test01DeniedAccessScreen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let denied = app.staticTexts["Keepwell needs photo access"]
        if !denied.waitForExistence(timeout: 8) {
            let allow = app.buttons["Allow Photo Access"]
            XCTAssertTrue(allow.waitForExistence(timeout: 10), "neither the denied nor the request screen appeared")
            allow.tap()
            XCTAssertNotNil(tapSystemButton(["Don’t Allow", "Don't Allow"], app: app), "no Photos permission alert")
        }
        XCTAssertTrue(denied.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Open Settings"].exists)
        shot("ui-denied")
    }

    /// Real batch delete: grant full access via the system alert, mark 3 photos, confirm the iOS delete alert,
    /// then check the freed bytes are above zero and the free deletes left dropped by the deleted count.
    func test02RealBatchDelete() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .photos)
        app.launch()

        let allow = app.buttons["Allow Photo Access"]
        if allow.waitForExistence(timeout: 10) {
            allow.tap()
            XCTAssertNotNil(tapSystemButton(["Allow Full Access", "Allow Access to All Photos", "OK"], app: app),
                            "no Photos permission alert")
        }

        let freeLeft = app.staticTexts["kw.freeDeletesLeft"]
        XCTAssertTrue(freeLeft.waitForExistence(timeout: 30), "home screen did not load")
        let before = try XCTUnwrap(leadingInt(freeLeft.label), "unparsable: \(freeLeft.label)")

        let month = app.buttons.matching(identifier: "kw.monthRow").firstMatch
        XCTAssertTrue(month.waitForExistence(timeout: 30), "no month rows")
        month.tap()

        let mark = app.buttons["Mark for deletion"]
        XCTAssertTrue(mark.waitForExistence(timeout: 15))
        let marks = 3
        for _ in 0..<marks {
            let enabled = NSPredicate(format: "isEnabled == true AND isHittable == true")
            expectation(for: enabled, evaluatedWith: mark)
            waitForExpectations(timeout: 10)
            mark.tap()
            Thread.sleep(forTimeInterval: 1.0)
        }

        let review = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Review ('")).firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        review.tap()

        let delete = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Delete '")).firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 15))
        let pendingCount = try XCTUnwrap(leadingInt(String(delete.label.dropFirst("Delete ".count))))
        XCTAssertGreaterThanOrEqual(pendingCount, marks)
        shot("ui-batch-tray")
        delete.tap()

        let gotIt = app.buttons["Got it, continue"]
        if gotIt.waitForExistence(timeout: 8) { gotIt.tap() }

        XCTAssertNotNil(tapSystemButton(["Delete", "Allow", "Delete Photos"], app: app, timeout: 40), "no iOS delete confirmation")

        let freed = app.staticTexts["kw.freedBytes"]
        XCTAssertTrue(freed.waitForExistence(timeout: 30), "freed summary did not appear")
        let freedLabel = freed.label
        let freedNumber = Double(freedLabel.prefix(while: { $0.isNumber || $0 == "." || $0 == "," })
            .replacingOccurrences(of: ",", with: "")) ?? 0
        XCTAssertGreaterThan(freedNumber, 0, "freed bytes label is \(freedLabel)")
        Thread.sleep(forTimeInterval: 1.5)
        shot("ui-batch-freed")

        app.buttons["Done"].tap()
        // Back to home: pop the tray and the session.
        for _ in 0..<3 where !freeLeft.exists {
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.exists { back.tap() }
            Thread.sleep(forTimeInterval: 0.8)
        }
        XCTAssertTrue(freeLeft.waitForExistence(timeout: 10))
        let after = try XCTUnwrap(leadingInt(freeLeft.label))
        XCTAssertEqual(after, before - pendingCount, "free deletes left: before \(before), after \(after)")
        XCTAssertLessThan(after, before)
        shot("ui-batch-home-after")
    }
}
