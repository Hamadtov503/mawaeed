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
        assertHandleLevelWithDayLine("after launch")
    }

    /// The tab's centre must be level with the home page's «اليوم» line (not just stay put).
    private func assertHandleLevelWithDayLine(_ step: String, file: StaticString = #filePath, line: UInt = #line) {
        let dayLine = app.descendants(matching: .any).matching(identifier: "dayLine").firstMatch
        XCTAssertTrue(dayLine.waitForExistence(timeout: 5), "day line missing: \(step)", file: file, line: line)
        XCTAssertEqual(handle.frame.midY, dayLine.frame.midY, accuracy: 8,
                       "tab not level with «اليوم»: \(step) (tab \(handle.frame.midY), line \(dayLine.frame.midY))",
                       file: file, line: line)
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
        assertHandleLevelWithDayLine("home after adding appointments")
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
        assertHandleLevelWithDayLine("after relaunch")
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
            if n == 1 {
                // Two icon buttons only; the second opens the grid, and picking an icon closes it.
                XCTAssertTrue(app.buttons["button.taskPhoto"].exists, "photo button missing")
                shot("10-icon-buttons")
                app.buttons["button.taskIcons"].tap()
                let cart = app.buttons["icon.cart.fill"]
                XCTAssertTrue(cart.waitForExistence(timeout: 3), "icon grid did not open")
                sleep(1)
                shot("10a-icon-grid")
                cart.tap()
                sleep(1)
                XCTAssertFalse(cart.exists, "icon grid stayed open after picking")
                shot("10b-icon-picked")
            }
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

        // On the home page a task can't be ticked directly: tapping it opens it, and it is done from there.
        XCTAssertFalse(app.buttons["تم"].exists, "the home page lets a task be ticked directly")
        element(containing: "Task 2").tap()
        XCTAssertTrue(app.buttons["button.toggleDone"].waitForExistence(timeout: 5), "tapping a task on home didn't open it")
        shot("14-task-opened-from-home")
        app.buttons["button.toggleDone"].tap()
        sleep(2)
        shot("15-home-after-done")
        assertHandle(at: base, "home after marking a task done")
    }

    /// A scheduled task: priority, icon, start now, an end; shown with its time range.
    func testScheduledTask() {
        launchToHome()
        go("tasks")
        app.buttons["addTask"].tap()
        let title = app.textFields["field.taskTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Report")
        element(containing: "عالية").tap()        // priority: high
        element(containing: "محدد بوقت").tap()    // scheduled
        sleep(1)
        shot("40-task-scheduled-form")
        XCTAssertTrue(app.buttons["row.date"].exists, "no end date row for a scheduled task")
        app.buttons["row.date"].tap()
        XCTAssertTrue(app.buttons[dayID(2)].waitForExistence(timeout: 4))
        app.buttons[dayID(2)].tap()
        sleep(1)
        shot("41-task-end-picked")
        app.buttons["button.save"].tap()
        sleep(2)
        shot("42-tasks-with-scheduled")
        XCTAssertTrue(element(containing: "Report").exists)
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

    /// Every top button must react exactly where it is drawn: the bell opens the notifications,
    /// the gear opens settings, and the month arrows only change the month. Checked on a fresh
    /// launch and again after adding an appointment (sheet + keyboard), and after a menu round trip.
    func testHeaderButtons() {
        launchToHome()
        checkHeaderButtons("launch")
        go("appointments")
        addAppointment(5, dayOffset: 2)
        go("home")
        sleep(1)
        assertHandleLevelWithDayLine("after adding an appointment")
        checkHeaderButtons("after-add")
        go("tasks")
        go("home")
        sleep(1)
        checkHeaderButtons("after-menu")
        // Scroll down and back up, then tap the header straight away.
        app.swipeUp()
        app.swipeDown()
        checkHeaderButtons("after-scroll")
        // Close a page and open the other one right away.
        app.buttons["button.profile"].tap()
        XCTAssertTrue(app.staticTexts["slidePage.title"].waitForExistence(timeout: 3))
        sleep(1)
        app.buttons["button.back"].tap()
        app.buttons["button.settings"].tap()   // straight away, while the profile is still sliding out
        let settingsTitle = app.staticTexts.matching(NSPredicate(format: "identifier == 'slidePage.title' AND label == 'الإعدادات'")).firstMatch
        XCTAssertTrue(settingsTitle.waitForExistence(timeout: 3), "the gear did not respond right after closing the profile")
        sleep(1)
        shot("hdr-quick-settings")
        app.buttons["button.back"].firstMatch.tap()
    }

    private func logFrames(_ step: String) {
        var lines: [String] = ["window \(app.windows.firstMatch.frame)"]
        for id in ["button.profile", "button.settings", "cal.title", "cal.prev", "cal.next", "dayLine", "menuHandle"] {
            let e = app.descendants(matching: .any).matching(identifier: id).firstMatch
            lines.append("\(id): \(e.exists ? "\(e.frame)" : "missing")")
        }
        let a = XCTAttachment(string: lines.joined(separator: "\n"))
        a.name = "frames-\(step)"
        a.lifetime = .keepAlways
        add(a)
    }

    private func checkHeaderButtons(_ step: String) {
        logFrames(step)
        shot("hdr-\(step)-0-home")
        let title = app.staticTexts["slidePage.title"]
        let back = app.buttons["button.back"]

        let bell = app.buttons["button.profile"]
        XCTAssertTrue(bell.waitForExistence(timeout: 4), "bell missing: \(step)")
        bell.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 3), "bell did not open a page: \(step)")
        XCTAssertEqual(title.label, "الملف الشخصي", "the profile button opened the wrong page: \(step)")
        sleep(1)
        shot("hdr-\(step)-1-bell")
        back.tap()
        sleep(1)
        XCTAssertFalse(title.exists, "back did not close notifications: \(step)")

        let gear = app.buttons["button.settings"]
        gear.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 3), "gear did not open a page: \(step)")
        XCTAssertEqual(title.label, "الإعدادات", "gear opened the wrong page: \(step)")
        sleep(1)
        shot("hdr-\(step)-2-settings")
        back.tap()
        sleep(1)
        XCTAssertFalse(title.exists, "back did not close settings: \(step)")

        let month = app.buttons["cal.title"]
        let before = month.label
        app.buttons["cal.next"].tap()
        sleep(1)
        XCTAssertFalse(title.exists, "the month arrow opened a page: \(step)")
        XCTAssertNotEqual(month.label, before, "the month arrow did not change the month: \(step)")
        shot("hdr-\(step)-3-next-month")
        app.buttons["cal.prev"].tap()
        sleep(1)
        XCTAssertFalse(title.exists, "the month arrow opened a page: \(step)")
        XCTAssertEqual(month.label, before, "back arrow did not return to this month: \(step)")
    }

    /// Menus and dialogs drawn by iOS (long-press menu, delete confirmation) must read normally,
    /// not mirrored. Checked by eye on the screenshots.
    func testSystemMenusNotMirrored() {
        launchToHome()
        go("appointments")
        addAppointment(7, dayOffset: 1)
        let card = element(containing: "Clinic 7")
        XCTAssertTrue(card.waitForExistence(timeout: 4))
        card.press(forDuration: 1.2)
        sleep(2)
        shot("50-long-press-menu")
        XCTAssertTrue(app.buttons["menuAction.حذف"].exists, "the long-press menu did not open")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()   // the dimmed area below the menu
        sleep(1)
        XCTAssertFalse(app.buttons["menuAction.حذف"].exists, "an outside tap did not close the menu")
        go("tasks")
        app.buttons["addTask"].tap()
        let title = app.textFields["field.taskTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Menu check")
        app.buttons["button.save"].tap()
        sleep(2)
        element(containing: "Menu check").tap()
        sleep(1)
        let delete = element(containing: "حذف المهمة")
        if delete.waitForExistence(timeout: 3) {
            delete.tap()
            sleep(1)
            shot("51-delete-dialog")
        }
    }

    /// After opening the Files picker from settings and leaving it (Cancel, or a swipe down),
    /// the settings page must still respond: its back button closes it.
    func testSettingsBackAfterFilesPicker() {
        launchToHome()
        for (i, id) in ["settings.exportBackup", "settings.importBackup"].enumerated() {
            app.buttons["button.settings"].tap()
            let row = app.buttons[id]
            XCTAssertTrue(row.waitForExistence(timeout: 4), "\(id) missing")
            row.tap()
            sleep(3)
            shot("60-\(i)-picker-\(id)")
            // Leave the picker: Cancel if it shows one, otherwise swipe the sheet down.
            let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["إلغاء", "Cancel"])).firstMatch
            if cancel.exists { cancel.tap() } else { app.swipeDown(velocity: .fast) }
            sleep(2)
            shot("61-\(i)-after-picker-\(id)")
            let back = app.buttons["button.back"]
            XCTAssertTrue(back.waitForExistence(timeout: 4), "back button missing after \(id)")
            back.tap()
            sleep(1)
            XCTAssertFalse(app.staticTexts["slidePage.title"].exists, "the back button did not close settings after \(id)")
            XCTAssertTrue(app.buttons["button.settings"].isHittable, "home is not usable after \(id)")
        }
    }

    /// The same screens in English.
    func testEnglish() {
        app.launchArguments = ["-uitest", "-lang-en", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        launchToHome()
        shot("30-en-home")
        go("appointments")
        addAppointment(9, dayOffset: 4)
        shot("31-en-appointments")
    }
}
