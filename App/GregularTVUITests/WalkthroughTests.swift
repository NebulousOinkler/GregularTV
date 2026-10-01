import XCTest

/// A walk through every screen with the Siri Remote, against the demo server
/// (`python3 scripts/demo-server.py`), in a Debug build. It exercises what the
/// keyboard can't reach in the simulator (moving the highlight, choosing,
/// typing into fields) and saves a screenshot at each step to `SHOTS_DIR`
/// (pass `TEST_RUNNER_SHOTS_DIR=…` to xcodebuild), for a person to look over.
/// Soft checks: a step that fails is recorded and the walk carries on.
@MainActor
final class WalkthroughTests: XCTestCase {
    private let app = XCUIApplication()
    private let remote = XCUIRemote.shared
    private var shot = 0

    override func setUp() async throws {
        continueAfterFailure = true
        app.launchArguments = ["-demoServer", "http://localhost:8765"]
        app.launch()
    }

    // MARK: Helpers

    private func pause(_ seconds: Double = 1.2) { Thread.sleep(forTimeInterval: seconds) }

    private func press(_ button: XCUIRemote.Button, times: Int = 1) {
        for _ in 0..<times {
            remote.press(button)
            pause(0.6)
        }
    }

    /// Saves a screenshot, numbered, to SHOTS_DIR.
    private func capture(_ name: String) {
        shot += 1
        guard let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] else { return }
        let test = self.name.split(separator: " ").last.map { String($0.dropLast()) } ?? "test"
        let url = URL(fileURLWithPath: dir).appendingPathComponent(String(format: "%@-%02d-%@.png", test, shot, name))
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
    }

    private func button(_ text: String) -> XCUIElement {
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func text(_ text: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Moves the highlight (down, by default) until `element` has it.
    @discardableResult
    private func focus(_ element: XCUIElement, moving direction: XCUIRemote.Button = .down, tries: Int = 40,
                       _ what: String) -> Bool {
        for _ in 0..<tries {
            if element.exists && element.hasFocus { return true }
            remote.press(direction)
            pause(0.35)
        }
        let ok = element.exists && element.hasFocus
        XCTAssertTrue(ok, "Couldn't reach \(what)")
        return ok
    }

    /// Chooses the button labelled `label`, moving down (then up) to reach it.
    @discardableResult
    private func choose(_ label: String) -> Bool {
        let target = button(label)
        guard focus(target, tries: 30, label) || focus(target, moving: .up, tries: 60, label) else { return false }
        press(.select)
        pause()
        return true
    }

    /// Types into the text field labelled `label` (the full-screen keyboard), then returns.
    private func type(_ value: String, into label: String) {
        let field = app.textFields.containing(NSPredicate(format: "placeholderValue CONTAINS %@ OR label CONTAINS %@", label, label)).firstMatch
        guard focus(field, tries: 30, label) || focus(field, moving: .up, tries: 60, label) else { return }
        press(.select)
        pause()
        app.typeText(value)
        pause(0.5)
        // The full-screen keyboard submits with its "done" button, below the keys.
        let done = app.buttons.matching(NSPredicate(format: "label ==[c] %@", "done")).firstMatch
        if !focus(done, tries: 8, "the keyboard's done button") { press(.menu) } else { press(.select) }
        pause()
    }

    private func openSettings() {
        remote.press(.select, forDuration: 1.2)   // click and hold
        pause(1.5)
        XCTAssertTrue(text("Settings").waitForExistence(timeout: 5), "Settings didn't open")
    }

    private func closeSettings() {
        press(.menu)
        pause()
    }

    /// The label of whatever has the highlight.
    private func focusedLabel() -> String {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch.label
    }

    /// Answers a confirmation dialog, whose buttons sit side by side:
    /// Cancel on the left (highlighted to start with), the action on the right.
    private func answerDialog(_ answer: String) {
        for _ in 0..<4 where focusedLabel() != answer {
            press(answer == "Cancel" ? .left : .right)
        }
        XCTAssertEqual(focusedLabel(), answer, "Couldn't highlight \(answer) in the dialog")
        press(.select)
        pause(1.5)
    }

    /// From watching, the guide: Menu hides the banner first if it's up.
    private func openGuide() {
        press(.menu)
        if !button("Settings").waitForExistence(timeout: 2) { press(.menu) }
        XCTAssertTrue(button("Settings").waitForExistence(timeout: 5), "The guide didn't open")
        pause()
    }

    /// Presses Menu until the guide (its Settings button) is gone: in the
    /// guide, Menu first steps back to now, then closes.
    private func backToLiveTV() {
        for _ in 0..<4 where button("Settings").exists {
            press(.menu)
            pause()
        }
        XCTAssertFalse(button("Settings").exists, "Couldn't get back to live TV")
    }

    /// Waits for live TV: the banner, with its remote hint, shows when it starts.
    private func waitForWatching() {
        let started = (0..<40).contains { _ in
            if text("channel list").exists { return true }
            pause(1)
            return false
        }
        XCTAssertTrue(started, "Never started watching")
        pause(6)
    }

    // MARK: Watching, the guide and Settings' switches

    func test1WatchingGuideAndSettings() throws {
        waitForWatching()
        capture("watching")
        press(.right)
        pause(3)
        capture("channel-up")
        press(.left)
        pause(3)

        openGuide()
        capture("guide")
        press(.down, times: 2)
        press(.right, times: 2)
        press(.select)
        pause(3)
        capture("guide-chose-a-programme")

        openGuide()
        press(.playPause)
        XCTAssertTrue(text("Streaming quality").waitForExistence(timeout: 5), "Play/Pause in the guide didn't open Settings")
        closeSettings()
        backToLiveTV()

        // Changing quality re-tunes; Settings must open again straight after.
        openSettings()
        choose("720p")
        pause(2)
        capture("just-after-720p")
        openSettings()
        capture("settings-straight-after-720p")
        closeSettings()
        pause(6)
        openSettings()
        capture("settings-later-after-720p")
        choose("Auto")
        pause(3)

        openSettings()
        type("NOPE", into: "Enter a code")
        XCTAssertTrue(text("10 letters and digits").exists, "No message for a bad schedule code")
        closeSettings()
    }

    // MARK: Settings opens on the quality in use

    func test5SettingsOpensOnTheQualityInUse() throws {
        waitForWatching()
        openSettings()
        XCTAssertTrue(text("Play/Pause, Menu or Done: close").exists, "The close hint isn't one line")
        choose("720p")
        pause(4)
        openSettings()
        capture("settings-opens-on-720p")
        XCTAssertTrue(focusedLabel().contains("720p"), "Opened on \(focusedLabel()), not 720p")
        choose("Auto")
        pause(2)
    }

    // MARK: The guide scrolling

    /// The times along the top and the channel names down the side follow
    /// the grid as it scrolls: compare the screenshots.
    func test6GuideScrolls() throws {
        waitForWatching()
        openGuide()
        capture("guide-at-start")
        press(.down, times: 6)
        press(.right, times: 10)
        pause()
        capture("guide-scrolled")
        XCTAssertTrue(button("Settings").exists, "The guide closed while scrolling")
        press(.left, times: 10)
        press(.up, times: 6)
        pause()
        capture("guide-back")
        backToLiveTV()
    }

    // MARK: A custom channel

    func test2CustomChannel() throws {
        waitForWatching()
        openSettings()
        choose("Add a Channel")
        XCTAssertTrue(text("New Channel").waitForExistence(timeout: 5), "The channel editor didn't open")
        type("Test Channel", into: "Channel name")
        choose("Movies")
        choose("A Genre")
        choose("Comedy")
        choose("Save")
        pause(4)
        openSettings()
        XCTAssertTrue(button("Test Channel").waitForExistence(timeout: 5), "The new channel isn't listed")
        capture("channel-listed")

        choose("Test Channel")
        XCTAssertTrue(text("Edit Channel").waitForExistence(timeout: 5), "The channel didn't open for editing")
        choose("Delete Channel")
        XCTAssertTrue(text("Delete channel").waitForExistence(timeout: 3), "Deleting didn't ask first")
        capture("delete-channel-asks")
        answerDialog("Cancel")
        XCTAssertTrue(text("Edit Channel").exists, "Cancel left the editor")
        choose("Delete Channel")
        answerDialog("Delete Channel")
        pause(4)
        openSettings()
        XCTAssertFalse(button("Test Channel").exists, "The channel is still listed after deleting")
        capture("channel-deleted")
        closeSettings()
    }

    // MARK: Set times

    func test3SetTimes() throws {
        waitForWatching()
        openSettings()
        choose("Set Times on a Channel")
        choose("1  Gregular")
        XCTAssertTrue(text("Set Times on 1").waitForExistence(timeout: 5), "The set-times editor didn't open")
        choose("Choose a series or film")
        press(.down)
        press(.select)
        pause()
        let calendar = Calendar.current
        let next = calendar.date(byAdding: .minute, value: 30 - calendar.component(.minute, from: .now) % 30, to: .now)!
        type(String(format: "%02d:%02d", calendar.component(.hour, from: next), calendar.component(.minute, from: next)), into: "Times")
        choose("Add Set Time")
        capture("set-time-added")
        choose("Save")
        pause(4)

        openSettings()
        XCTAssertTrue(button("1  Gregular").waitForExistence(timeout: 5), "The set times aren't listed")
        capture("set-times-listed")
        closeSettings()
        press(.left)   // channel 1 is where the set time is: it's the first channel
        pause(2)
        openGuide()
        capture("guide-with-set-time")
        press(.menu)
        pause()

        openSettings()
        choose("1  Gregular")
        choose("Delete Set Times")
        XCTAssertTrue(text("Delete the set times").waitForExistence(timeout: 3), "Deleting set times didn't ask first")
        capture("delete-set-times-asks")
        answerDialog("Delete Set Times")
        pause(4)
        capture("after-deleting-set-times")
        backToLiveTV()   // Settings was opened from the guide, so it went back there
        openSettings()
        XCTAssertFalse(button("1  Gregular").exists, "The set times are still listed after deleting")
        closeSettings()
    }

    // MARK: Codes, signing out and signing in

    func test4CodesAndSigningOut() throws {
        waitForWatching()
        openSettings()
        type("NOT-A-CODE", into: "channel code")
        XCTAssertTrue(text("isn't a channel code").exists, "No message for a bad channel code")
        capture("channel-code-rejected")
        type("NOT-A-CODE", into: "set-times code")
        XCTAssertTrue(text("isn't a set-times code").exists, "No message for a bad set-times code")
        capture("set-times-code-rejected")

        choose("Sign Out")
        XCTAssertTrue(text("Sign out of Jellyfin?").waitForExistence(timeout: 3), "Signing out didn't ask first")
        capture("sign-out-asks")
        answerDialog("Cancel")
        XCTAssertTrue(text("Streaming quality").exists || button("Sign Out").exists, "Cancel didn't stay in Settings")
        choose("Sign Out")
        answerDialog("Sign Out")
        pause(3)
        capture("signed-out")

        type("http://media.example.com", into: "192.168.1.10")
        choose("Connect")
        pause(2)
        XCTAssertTrue(text("Plain http only works on your home network").exists, "No message for plain http to the internet")
        capture("sign-in-insecure-address")
        type("localhost:8765", into: "192.168.1.10")
        choose("Connect")
        pause(5)
        capture("sign-in-demo-server")
    }
}
