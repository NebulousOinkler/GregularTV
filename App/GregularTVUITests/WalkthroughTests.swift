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

    /// Moves the highlight (down, by default) until `element` has it. Not
    /// reaching it isn't a failure here: callers often try the other way next.
    private func focus(_ element: XCUIElement, moving direction: XCUIRemote.Button = .down, tries: Int = 40) -> Bool {
        for _ in 0..<tries {
            if element.exists && element.hasFocus { return true }
            remote.press(direction)
            pause(0.35)
        }
        return element.exists && element.hasFocus
    }

    /// Moves the highlight towards `element` while it's on screen (grids
    /// need left and right too), then down, then up, until it has it; a
    /// failure only if it's in no direction.
    private func reach(_ element: XCUIElement, _ what: String) -> Bool {
        for _ in 0..<20 where element.exists && !element.hasFocus {
            let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
            guard focused.exists else { break }
            let (from, to) = (focused.frame, element.frame)
            let direction: XCUIRemote.Button = to.minY >= from.maxY ? .down : to.maxY <= from.minY ? .up
                : to.midX > from.midX ? .right : .left
            remote.press(direction)
            pause(0.35)
        }
        let ok = focus(element, tries: 30) || focus(element, moving: .up, tries: 60)
        XCTAssertTrue(ok, "Couldn't reach \(what)")
        return ok
    }

    /// Chooses the button labelled `label`, moving down (then up) to reach it.
    @discardableResult
    private func choose(_ label: String) -> Bool {
        guard reach(button(label), label) else { return false }
        press(.select)
        pause()
        return true
    }

    /// Types into the text field labelled `label` (the full-screen keyboard), then returns.
    private func type(_ value: String, into label: String) {
        let field = app.textFields.containing(NSPredicate(format: "placeholderValue CONTAINS %@ OR label CONTAINS %@", label, label)).firstMatch
        guard reach(field, label) else { return }
        press(.select)
        pause()
        app.typeText(value)
        pause(0.5)
        // The full-screen keyboard submits with its "done" button, below the keys.
        let done = app.buttons.matching(NSPredicate(format: "label ==[c] %@", "done")).firstMatch
        if !focus(done, tries: 8) { press(.menu) } else { press(.select) }
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

    /// From watching, the guide: Menu (twice if the banner was up).
    private func openGuide() {
        press(.menu)
        if !button("Resume Live TV").waitForExistence(timeout: 2) { press(.menu) }
        XCTAssertTrue(button("Resume Live TV").waitForExistence(timeout: 5), "Menu didn't open the guide")
        pause()
    }

    /// The guide's top row (Resume Live TV, Settings): Menu, unless it's
    /// already there (Up from the first channel reaches it too).
    private func toTopRow() {
        if !focusedLabel().contains("Resume Live TV") && !focusedLabel().contains("Settings") { press(.menu) }
    }

    /// From the guide: up to Resume Live TV, and a click there goes back to the channel.
    private func backToLiveTV() {
        toTopRow()
        if focusedLabel().contains("Settings") { press(.left) }
        XCTAssertTrue(focusedLabel().contains("Resume Live TV"), "Menu didn't move up to Resume: \(focusedLabel())")
        press(.select)
        pause()
        XCTAssertFalse(button("Resume Live TV").exists, "Resume didn't close the guide")
        XCTAssertFalse(text("Add a Server").exists, "Resume went to the main page, not live TV")
    }

    /// Waits for live TV: the banner, with its remote hint, shows when it
    /// starts. The app opens on the main page, so first choose the server
    /// (the one watched last is highlighted).
    private func waitForWatching() {
        if text("Add a Server").waitForExistence(timeout: 15) {
            press(.select)
        }
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

        // Settings from the guide: Menu up to the top row, right, click.
        openGuide()
        toTopRow()
        press(.right)
        press(.select)
        XCTAssertTrue(text("Streaming quality").waitForExistence(timeout: 5), "Settings in the guide didn't open Settings")
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

    // MARK: The editing page

    /// Off by default; turned on, Settings opens a screen with the address
    /// and code. (Making channels and set times happens in the browser:
    /// `EditingPageTests` covers what the page accepts.)
    func test2EditingPage() throws {
        waitForWatching()
        openSettings()
        XCTAssertFalse(button("Open the Editing Page").exists, "The editing page should be off by default")
        XCTAssertFalse(button("Add a Channel").exists, "Channels are made on the editing page, not here")
        choose("Editing page")
        XCTAssertTrue(button("Open the Editing Page").waitForExistence(timeout: 3), "Turning it on didn't offer the page")
        choose("Open the Editing Page")
        XCTAssertTrue(text("Then enter this code").waitForExistence(timeout: 10), "The page's address and code didn't show")
        capture("editing-page")
        choose("Done")
        pause()
        // Back on "Open the Editing Page"; the switch is just above. (After a
        // full-screen screen closes, `choose`'s long search misses rows, so step.)
        press(.up)
        XCTAssertTrue(focusedLabel().hasPrefix("Editing page"), "Up didn't reach the switch: \(focusedLabel())")
        press(.select)   // back off, as it started
        pause()
        XCTAssertFalse(button("Open the Editing Page").exists, "Turning it off didn't hide the page")
        closeSettings()
    }

    // MARK: The main page

    /// Menu, one step at a time: live TV → guide → Resume Live TV → main
    /// page → Home screen. The app opens on the servers; a click goes in.
    /// From the main page, a click on the server playing behind it goes
    /// straight back, without loading again.
    func test7MainPage() throws {
        XCTAssertTrue(text("Add a Server").waitForExistence(timeout: 15), "The app didn't open on the main page")
        XCTAssertTrue(text("Watched last").exists, "The server watched last isn't marked")
        capture("main-page")
        waitForWatching()
        openGuide()
        capture("guide")
        backToLiveTV()

        openGuide()
        press(.menu)   // up to Resume
        XCTAssertTrue(focusedLabel().contains("Resume Live TV"), "Menu didn't move up to Resume: \(focusedLabel())")
        capture("guide-resume")
        press(.menu)   // up to the main page
        XCTAssertTrue(text("Add a Server").waitForExistence(timeout: 5), "Menu from Resume didn't go up to the main page")
        XCTAssertTrue(text("Now playing").exists, "The server playing behind the page isn't marked")
        capture("main-page-over-live-tv")
        press(.select)
        XCTAssertTrue(text("channel list").waitForExistence(timeout: 3), "Choosing the server didn't go straight back to live TV")
        XCTAssertFalse(text("Loading your library…").exists, "Going back loaded the library again")
        pause(0.5)
        capture("back-to-live-tv")

        openGuide()
        press(.menu)
        press(.right)   // Settings, on the same row: Menu from there goes up too
        XCTAssertTrue(focusedLabel().contains("Settings"), "Right didn't reach Settings: \(focusedLabel())")
        press(.menu)
        XCTAssertTrue(text("Add a Server").waitForExistence(timeout: 5), "Menu from Settings' row didn't go up to the main page")
        press(.playPause)
        XCTAssertTrue(text("channel list").waitForExistence(timeout: 3), "Play/Pause didn't go back to live TV")

        openGuide()
        press(.menu)
        press(.menu)
        XCTAssertTrue(text("Add a Server").waitForExistence(timeout: 5), "Menu didn't go up to the main page")
        press(.menu)
        let left = expectation(for: NSPredicate(format: "state != %d", XCUIApplication.State.runningForeground.rawValue),
                               evaluatedWith: app)
        wait(for: [left], timeout: 5)   // fails the test if the app's still showing
    }

    // MARK: Signing out and signing in

    func test4SigningOutAndIn() throws {
        waitForWatching()
        openSettings()
        choose("Sign Out")
        // The server's name once the main page has asked for it (the demo server's), its address until then.
        let asked = text("Sign out of Demo Library?").waitForExistence(timeout: 3) || text("Sign out of localhost:8765?").exists
        XCTAssertTrue(asked, "Signing out didn't ask first")
        capture("sign-out-asks")
        answerDialog("Cancel")
        XCTAssertTrue(text("Streaming quality").exists || button("Sign Out").exists, "Cancel didn't stay in Settings")
        choose("Sign Out")
        answerDialog("Sign Out")
        pause(3)
        // Back to the main page. (Demo mode can't forget its one server, so
        // it's still listed; a real sign-out with no servers left shows sign-in.)
        XCTAssertTrue(text("Add a Server").waitForExistence(timeout: 5), "Signing out didn't go to the main page")
        capture("signed-out")

        press(.right)   // the cards sit side by side: from the server to Add a Server
        XCTAssertTrue(focusedLabel().contains("Add a Server"), "Right didn't reach Add a Server: \(focusedLabel())")
        press(.select)
        XCTAssertTrue(button("Cancel").waitForExistence(timeout: 5), "Adding a server should offer Cancel back to the main page")
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

    // MARK: Karaoke

    /// Karaoke's keyword, from `TEST_RUNNER_SPECIAL_MODE_KEYWORD`: the repo
    /// keeps only its hash, so the keyword itself is never written here.
    private func keyword() throws -> String {
        guard let keyword = ProcessInfo.processInfo.environment["SPECIAL_MODE_KEYWORD"], !keyword.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_SPECIAL_MODE_KEYWORD to walk through karaoke")
        }
        return keyword
    }

    /// Its keyword, typed where a schedule code goes, opens karaoke: the
    /// theme boxes (each sampled in turn), its menu, a song loaded whole and
    /// held on its title card, the song's lyrics, the cheer when it ends,
    /// and Leave Karaoke back to live TV.
    func test8Karaoke() throws {
        let keyword = try keyword()
        waitForWatching()
        openSettings()
        type(keyword, into: "Enter a code")
        guard text("Pick a Theme").waitForExistence(timeout: 10) else { return XCTFail("The keyword didn't open karaoke") }
        capture("karaoke-themes")
        for theme in ["bar", "bubblegum", "vegas"] {
            press(.right)
            pause(1)
            capture("karaoke-theme-\(theme)")
        }
        for _ in 0..<3 { press(.left) }
        press(.select)
        guard button("All Songs").waitForExistence(timeout: 5) else { return XCTFail("Choosing a theme didn't open karaoke's menu") }
        pause(1)
        capture("karaoke-menu")
        press(.menu)
        XCTAssertTrue(button("All Songs").exists, "Menu left karaoke's menu with nothing to go back to")
        choose("All Songs")
        XCTAssertTrue(button("Bubble Bath Ballad").waitForExistence(timeout: 5), "No songs listed")
        pause(1)
        capture("karaoke-songs")
        XCTAssertTrue(button("Jump to S").exists, "A long list has letters to jump by")
        choose("Saturday Satellite")
        guard text("Press Play to sing").waitForExistence(timeout: 20) else { return XCTFail("The song didn't load") }
        capture("karaoke-title-card")
        press(.playPause)
        XCTAssertTrue(text("Spin").waitForExistence(timeout: 10), "No lyrics while singing")
        pause(2)
        capture("karaoke-singing")
        XCTAssertTrue(text("Encore!").waitForExistence(timeout: 20), "No cheer at the end of the song")
        pause(0.8)
        capture("karaoke-encore")
        pause(4)
        press(.select)
        XCTAssertTrue(button("Artists").waitForExistence(timeout: 5), "Any button on the attract screen opens the menu")
        choose("Leave Karaoke")
        answerDialog("Leave Karaoke")
        XCTAssertTrue(text("channel list").waitForExistence(timeout: 20), "Leaving karaoke didn't go back to live TV")
        capture("karaoke-left")
    }

    /// Karaoke in each theme: its menu and a long list, then a song on its
    /// title card and sung, in the last theme. For looking at, mostly.
    func test11KaraokeInEachTheme() throws {
        let keyword = try keyword()
        waitForWatching()
        openSettings()
        type(keyword, into: "Enter a code")
        guard text("Pick a Theme").waitForExistence(timeout: 10) else { return XCTFail("The keyword didn't open karaoke") }
        for (index, theme) in ["neon", "bar", "bubblegum", "vegas"].enumerated() {
            if index > 0 {
                guard choose("Change Theme") else { return }
                pause(1)
                for _ in 0..<3 { press(.left) }
                press(.right, times: index)
            }
            press(.select)
            guard button("All Songs").waitForExistence(timeout: 5) else { return XCTFail("No menu in \(theme)") }
            pause(1)
            capture("\(theme)-menu")
            choose("All Songs")
            pause(1.5)
            capture("\(theme)-songs")
            press(.menu)
            pause(1)
        }
        choose("Search")
        press(.menu)
        choose("All Songs")
        choose("Disco Lemonade")
        guard text("Press Play to sing").waitForExistence(timeout: 20) else { return XCTFail("The song didn't load") }
        pause(1)
        capture("vegas-title-card")
        press(.playPause)
        pause(6)
        capture("vegas-singing")
        press(.menu)
        choose("Leave Karaoke")
        answerDialog("Leave Karaoke")
    }

    /// Songs from Phones: off until turned on in karaoke's menu; then a
    /// phone on the home network, with the address and code on the TV,
    /// adds a song (asking as the picker page does), and the TV says so.
    func test9KaraokeFromAPhone() throws {
        let keyword = try keyword()
        waitForWatching()
        openSettings()
        type(keyword, into: "Enter a code")
        guard text("Pick a Theme").waitForExistence(timeout: 10) else { return XCTFail("The keyword didn't open karaoke") }
        press(.select)
        guard choose("Songs from Phones") else { return }
        XCTAssertTrue(button("Let phones add songs: Off").exists, "Phones should be off to begin with")
        choose("Let phones add songs")
        let code = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "[0-9]{6}")).firstMatch
        guard code.waitForExistence(timeout: 10) else { return XCTFail("No code for phones") }
        let address = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "http://")).firstMatch.label
        capture("karaoke-phones")

        let status = phoneAsks(address, "POST", "/api/queue", code: code.label, body: #"{"id":"song0"}"#)
        XCTAssertEqual(status, 200, "The phone's song wasn't taken")
        XCTAssertTrue(text("A phone added").waitForExistence(timeout: 5), "The TV didn't say a phone added a song")
        XCTAssertTrue(text("Pick a Theme").exists == false && button("Let phones add songs: On").exists,
                      "A phone's song shouldn't move the TV off its menu")
        press(.menu)
        press(.menu)
        XCTAssertTrue(text("Add songs from your phone").waitForExistence(timeout: 10), "The stage doesn't say where phones go")
        capture("karaoke-phone-badge")
        press(.menu)
        choose("Leave Karaoke")
        answerDialog("Leave Karaoke")
        XCTAssertTrue(text("channel list").waitForExistence(timeout: 20), "Leaving karaoke didn't go back to live TV")
    }

    /// A request as a phone's browser sends it, to the page at `address`
    /// ("http://192.168.1.20:8080"), and the status of the reply. Sent over
    /// loopback, with the address as its Host: a test can't be given the
    /// local-network permission a real phone's browser has.
    private func phoneAsks(_ address: String, _ method: String, _ path: String, code: String, body: String) -> Int {
        let host = String(address.dropFirst("http://".count))
        guard let port = host.split(separator: ":").last.flatMap({ Int($0) }) else { return 0 }
        let request = "\(method) \(path) HTTP/1.1\r\nHost: \(host)\r\nX-Gregular-Code: \(code)\r\n"
            + "Content-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        var input: InputStream?
        var output: OutputStream?
        Stream.getStreamsToHost(withName: "127.0.0.1", port: port, inputStream: &input, outputStream: &output)
        guard let input, let output else { return 0 }
        input.open()
        output.open()
        defer { input.close(); output.close() }
        let bytes = Array(request.utf8)
        guard output.write(bytes, maxLength: bytes.count) == bytes.count else { return 0 }
        var reply = [UInt8](repeating: 0, count: 4096)
        let deadline = Date.now.addingTimeInterval(10)
        while !input.hasBytesAvailable, Date.now < deadline { Thread.sleep(forTimeInterval: 0.05) }
        let count = input.read(&reply, maxLength: reply.count)
        guard count > 0, let line = String(decoding: reply.prefix(count), as: UTF8.self).split(separator: "\r\n").first else { return 0 }
        return line.split(separator: " ").dropFirst().first.flatMap { Int($0) } ?? 0
    }

    // MARK: VLC, for files Apple TV's own player can't play as they are

    /// With the demo server started with `--fallback`, films and shows play
    /// in VLC: the diagnostics line says so (playing, not stuck buffering),
    /// with Match frame rate on. Skipped without `--fallback`.
    func test10FallbackPlayer() throws {
        try XCTSkipUnless(Self.serverSendsProgrammesToVLC(), "Start the demo server with --fallback")
        waitForWatching()
        openSettings()
        // Its line says what's playing. The TV follows each channel's frame
        // rate meanwhile (the simulator doesn't switch, but it's asked).
        let changed = ["Show playback diagnostics", "Match frame rate"].filter { setSwitch($0, on: true) }
        closeSettings()

        // On one channel or the other, a programme (not a break).
        let seen = (0..<16).contains { _ in
            press(.right)   // channel up: the banner shows, with the diagnostics line
            pause(4)
            return text("Playing in VLC").exists
        }
        XCTAssertTrue(seen, "No programme played in VLC")
        capture("playing-in-vlc")

        openSettings()
        for label in changed { setSwitch(label, on: false) }
        closeSettings()
    }

    /// Turns the Settings switch labelled `label` on or off. True if it changed.
    @discardableResult
    private func setSwitch(_ label: String, on: Bool) -> Bool {
        let row = button(label)
        guard reach(row, label), row.label.hasSuffix(on ? "Off" : "On") else { return false }
        press(.select)
        XCTAssertTrue(focusedLabel().hasSuffix(on ? "On" : "Off"), "\(label) didn't turn \(on ? "on" : "off"): \(focusedLabel())")
        return true
    }

    /// Asks the demo server about a film for Apple TV's own player, as the app does.
    private static func serverSendsProgrammesToVLC() -> Bool {
        var request = URLRequest(url: URL(string: "http://localhost:8765/Items/film1/PlaybackInfo")!)
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"DeviceProfile": {"Name": "Gregular (tvOS)"}}"#.utf8)
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var plays = true
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let sources = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])?["MediaSources"]
            plays = ((sources as? [[String: Any]])?.first?["SupportsDirectPlay"] as? Bool) ?? true
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 5)
        return !plays
    }
}
