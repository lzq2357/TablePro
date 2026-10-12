//
//  VirtualForeignKeyConfigUITests.swift
//  TableProUITests
//

import XCTest

/// The Virtual Keys tab end to end: the tab is offered, a key is configured against the sample's
/// own tables, edits and deletes land in the list, and the configuration survives a relaunch
/// because it lives in TablePro's own storage rather than in the database.
final class VirtualForeignKeyConfigUITests: UITestCase {
    func testConfigureEditAndDeleteAVirtualForeignKey() throws {
        let app = try launchWithSampleDatabase()
        let window = app.windows.firstMatch

        try openVirtualKeysTab(app: app, window: window)

        XCTAssertTrue(
            window.staticTexts["No Virtual Foreign Keys"].waitToExist(timeout: 20),
            "An unconfigured table must show the empty state"
        )

        let add = window.buttons["virtual-fk-add"].firstMatch
        XCTAssertTrue(add.waitToExist(timeout: 10), "The Virtual Keys tab must offer an add button")
        add.click()

        let sheet = window.sheets.firstMatch
        XCTAssertTrue(sheet.waitToExist(timeout: 10), "Add must open the editor sheet")

        let save = sheet.buttons["virtual-fk-editor-save"].firstMatch
        XCTAssertTrue(save.waitToExist(timeout: 10))
        XCTAssertFalse(save.isEnabled, "An empty draft must not be savable")

        choose("ArtistId", from: "virtual-fk-editor-column", in: sheet, app: app)
        choose("Artist", from: "virtual-fk-editor-ref-table", in: sheet, app: app)
        choose("ArtistId", from: "virtual-fk-editor-ref-column", in: sheet, app: app)

        XCTAssertTrue(
            waitForPredicate(timeout: 10) { save.isEnabled },
            "A complete draft must enable Save"
        )
        save.click()

        XCTAssertTrue(
            waitForPredicate(timeout: 10) { !sheet.exists },
            "Save must close the editor"
        )
        let listedTarget = window.staticTexts["Artist"].firstMatch
        XCTAssertTrue(listedTarget.waitToExist(timeout: 10), "The saved key must appear in the list")

        clickAtCenter(listedTarget)
        let edit = window.buttons["virtual-fk-edit"].firstMatch
        XCTAssertTrue(
            waitForPredicate(timeout: 10) { edit.isEnabled },
            "Selecting a key must enable Edit"
        )
        edit.click()
        XCTAssertTrue(sheet.waitToExist(timeout: 10), "Edit must open the editor sheet")
        choose("Name", from: "virtual-fk-editor-ref-column", in: sheet, app: app)
        XCTAssertTrue(waitForPredicate(timeout: 10) { save.isEnabled })
        save.click()
        XCTAssertTrue(
            window.staticTexts["Name"].firstMatch.waitToExist(timeout: 10),
            "The edited referenced column must appear in the list"
        )

        clickAtCenter(window.staticTexts["Artist"].firstMatch)
        let delete = window.buttons["virtual-fk-delete"].firstMatch
        XCTAssertTrue(waitForPredicate(timeout: 10) { delete.isEnabled })
        delete.click()
        let remove = app.buttons["Remove"].firstMatch
        XCTAssertTrue(remove.waitToExist(timeout: 10), "Delete must ask before removing")
        remove.click()
        XCTAssertTrue(
            window.staticTexts["No Virtual Foreign Keys"].waitToExist(timeout: 10),
            "Deleting the only key must bring the empty state back"
        )
    }

    func testVirtualForeignKeySurvivesRelaunch() throws {
        let first = try launchWithSampleDatabase()
        let firstWindow = first.windows.firstMatch

        try openVirtualKeysTab(app: first, window: firstWindow)

        let add = firstWindow.buttons["virtual-fk-add"].firstMatch
        XCTAssertTrue(add.waitToExist(timeout: 20))
        add.click()

        let sheet = firstWindow.sheets.firstMatch
        XCTAssertTrue(sheet.waitToExist(timeout: 10))
        choose("ArtistId", from: "virtual-fk-editor-column", in: sheet, app: first)
        choose("Artist", from: "virtual-fk-editor-ref-table", in: sheet, app: first)
        choose("ArtistId", from: "virtual-fk-editor-ref-column", in: sheet, app: first)

        let save = sheet.buttons["virtual-fk-editor-save"].firstMatch
        XCTAssertTrue(waitForPredicate(timeout: 10) { save.isEnabled })
        save.click()
        XCTAssertTrue(firstWindow.staticTexts["Artist"].firstMatch.waitToExist(timeout: 10))

        first.terminate()

        let second = try launchWithSampleDatabase()
        let secondWindow = second.windows.firstMatch
        try openVirtualKeysTab(app: second, window: secondWindow)

        XCTAssertTrue(
            secondWindow.staticTexts["Artist"].firstMatch.waitToExist(timeout: 20),
            "A configured virtual foreign key must survive a relaunch"
        )
    }

    private func openVirtualKeysTab(app: XCUIApplication, window: XCUIElement) throws {
        let row = objectBrowserRow("Album", in: window)
        XCTAssertTrue(row.waitToExist(timeout: 20), "The object browser must list Album")
        clickAtCenter(row)

        showStructure(in: app, window: window)

        /// Matched by prefix the way the Foreign Keys suite matches its own sub-tab, so a count
        /// badge added later cannot break the lookup.
        let virtualKeys = window.radioGroups["structure-tab-picker"].firstMatch
            .radioButtons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Virtual Keys"))
            .firstMatch
        XCTAssertTrue(
            virtualKeys.waitToExist(timeout: 20),
            "Every engine must offer the Virtual Keys tab"
        )
        virtualKeys.click()
    }

    /// Opens the identified picker or menu and clicks `item` once the list offers it. The table
    /// and column lists load asynchronously, so a menu opened before the fetch landed shows only
    /// `Loading…`; closing and reopening it is the retry the menu itself documents.
    private func choose(
        _ item: String,
        from identifier: String,
        in sheet: XCUIElement,
        app: XCUIApplication
    ) {
        let control = sheet.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
        XCTAssertTrue(control.waitToExist(timeout: 10), "The editor must offer \(identifier)")

        for _ in 0 ..< 4 {
            control.click()
            let menuItem = app.menuItems[item].firstMatch
            if waitForPredicate(timeout: 3, { menuItem.exists && menuItem.isHittable }) {
                menuItem.click()
                return
            }
            app.typeKey(.escape, modifierFlags: [])
        }
        XCTFail("The \(identifier) menu never offered \(item)")
    }
}
