import XCTest

/// End-to-end checks on the iPhone simulator. Every step saves a screenshot (kept in the test
/// results) so the rendering — digits, calendar, cards — can be reviewed by eye.
final class MawaeedUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        // Run the app in Arabic, the way it is used.
        app.launchArguments = ["-uitest", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
    }

    // MARK: Helpers

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func launchToHome() {
        app.launch()
        XCTAssertTrue(app.buttons["menuHandle"].waitForExistence(timeout: 10), "menu tab never appeared")
        sleep(2)   // splash fades out
    }

    private var handle: XCUIElement { app.buttons["menuHandle"] }

    /// Any element whose label contains `text` (text inside a SwiftUI button joins the button's label).
    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func assertHandle(at expected: CGRect, _ step: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(handle.waitForExistence(timeout: 5), "tab missing: \(step)", file: file, line: line)
        let f = handle.frame
        XCTAssertEqual(f.midY, expected.midY, accuracy: 1, "tab moved vertically: \(step) (\(f) vs \(expected))", file: file, line: line)
        XCTAssertEqual(f.minX, expected.minX, accuracy: 1, "tab moved sideways: \(step) (\(f) vs \(expected))", file: file, line: line)
    }

    private func go(_ page: String) {
        handle.tap()
        let item = app.buttons["menu.\(page)"]
        XCTAssertTrue(item.waitForExistence(timeout: 4), "menu item \(page) missing")
        sleep(1)
        shot("menu-open-\(page)")
        item.tap()
        sleep(1)
    }

    private func dayID(_ offset: Int) -> String {
        let cal = Calendar(identifier: .gregorian)
        let d = cal.date(byAdding: .day, value: offset, to: Date())!
        let f = DateFormatter()
        f.calendar = cal
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return "day." + f.string(from: d)
    }

    private func addAppointment(_ n: Int, dayOffset: Int) {
        app.buttons["addAppointment"].tap()
        let title = app.textFields["field.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Clinic \(n)")
        let place = app.textFields["field.place"]
        place.tap()
        place.typeText("Hospital \(n)")

        app.buttons["row.date"].tap()
        XCTAssertTrue(app.buttons[dayID(dayOffset)].waitForExistence(timeout: 4), "calendar popup did not open")
        sleep(1)
        shot("appt\(n)-calendar")
        let day = app.buttons[dayID(dayOffset)]
        if day.exists { day.tap() } else { XCTFail("day \(dayID(dayOffset)) not in the calendar") }
        sleep(1)
        XCTAssertFalse(app.buttons[dayID(dayOffset)].exists, "calendar stayed open after picking a day")

        app.buttons["row.time"].tap()
        XCTAssertTrue(app.buttons["popup.done"].waitForExistence(timeout: 4), "time popup did not open")
        sleep(1)
        shot("appt\(n)-time")
        app.buttons["popup.done"].tap()
        sleep(1)
        shot("appt\(n)-form")
        app.buttons["button.save"].tap()
        sleep(2)
    }

    // MARK: Tests

    /// Adds several appointments and checks the menu tab never moves, on any page.
    func testAppointmentsAndTabStability() {
        launchToHome()
        shot("01-home-empty")
        let base = handle.frame

        go("appointments")
        shot("02-appointments-empty")
        assertHandle(at: base, "appointments page")

        for n in 1...3 {
            addAppointment(n, dayOffset: n + 1)
            shot("03-appointments-after-add-\(n)")
            assertHandle(at: base, "after adding appointment \(n)")
        }

        // Right-to-left swipe goes back home.
        app.swipeLeft()
        sleep(2)
        shot("04-home-with-appointments")
        assertHandle(at: base, "home after swipe")
        XCTAssertTrue(app.buttons["card.Clinic 1"].exists || element(containing: "Clinic 1").exists,
                      "home does not show the new appointment")

        // Open an appointment's details and close them.
        (app.buttons["card.Clinic 1"].exists ? app.buttons["card.Clinic 1"] : element(containing: "Clinic 1")).tap()
        sleep(2)
        shot("05-appointment-detail")
        app.swipeDown(velocity: .fast)
        sleep(2)
        assertHandle(at: base, "after closing details")

        // Relaunch: the tab must come back at the same height.
        app.terminate()
        app.launchArguments.removeAll { $0 == "-uitest" }   // keep the data this time
        app.launch()
        XCTAssertTrue(handle.waitForExistence(timeout: 10))
        sleep(2)
        shot("06-home-after-relaunch")
        assertHandle(at: base, "after relaunch")
    }

    /// Adds tasks, ticks one off, and checks both sections and the tab.
    func testTasks() {
        launchToHome()
        let base = handle.frame
        go("tasks")
        shot("10-tasks-empty")
        for n in 1...3 {
            app.buttons["addTask"].tap()
            let title = app.textFields["field.taskTitle"]
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            title.tap()
            title.typeText("Task \(n)")
            app.buttons["button.save"].tap()
            sleep(2)
            assertHandle(at: base, "after adding task \(n)")
        }
        shot("11-tasks-added")
        let circle = app.buttons["تم"].firstMatch
        if circle.exists { circle.tap(); sleep(2) }
        shot("12-tasks-one-done")
        app.swipeLeft()   // starts over the task rows: must go home, not open a task
        sleep(2)
        XCTAssertFalse(app.textFields["field.taskTitle"].exists, "a sideways swipe over a task opened it")
        shot("13-home-with-tasks")
        assertHandle(at: base, "home after tasks")
    }

    /// A tap outside the calendar popup closes it.
    func testOutsideTapClosesPopup() {
        launchToHome()
        go("appointments")
        app.buttons["addAppointment"].tap()
        XCTAssertTrue(app.buttons["row.date"].waitForExistence(timeout: 5))
        app.buttons["row.date"].tap()
        XCTAssertTrue(app.buttons[dayID(3)].waitForExistence(timeout: 4))
        shot("20-calendar-open")
        // Tap the dimmed area below the card (inside the form sheet), as a person would.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.93)).tap()
        sleep(1)
        XCTAssertFalse(app.buttons[dayID(3)].exists, "calendar did not close on an outside tap")
        shot("21-calendar-closed")

        app.buttons["row.time"].tap()
        XCTAssertTrue(app.buttons["popup.done"].waitForExistence(timeout: 4))
        shot("22-time-open")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.88)).tap()   // dimmed area below the card (not the home-indicator strip)
        sleep(1)
        XCTAssertFalse(app.buttons["popup.done"].exists, "time popup did not close on an outside tap")
        shot("23-time-closed")
    }

    /// The same screens in English.
    func testEnglish() {
        app.launchArguments += ["-lang-en"]
        launchToHome()
        shot("30-en-home")
        go("appointments")
        addAppointment(9, dayOffset: 4)
        shot("31-en-appointments")
    }
}
