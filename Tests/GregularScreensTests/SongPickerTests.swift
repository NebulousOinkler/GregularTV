import Foundation
import GregularCore
import Testing
@testable import GregularScreens

/// Karaoke's song picker: phones on the home network adding songs to the
/// queue, behind the same guard as the editing page (`LocalPage`).
@MainActor
struct SongPickerTests {
    static let host = "192.168.1.20:8080"
    let deck = FakeSongDeck()

    private func karaoke(phones: Bool = true) -> KaraokeModel {
        let karaoke = KaraokeModel(session: Songs.session(), deck: deck, offersPhones: true)
        karaoke.choose(.neonDisco)
        karaoke.setPhonesAllowed(phones)
        return karaoke
    }

    private func ask(_ page: LocalPage, _ method: String, _ path: String, body: String = "", code: String = "123456") async -> HTTPResponse {
        let text = "\(method) \(path) HTTP/1.1\r\nHost: \(Self.host)\r\nX-Gregular-Code: \(code)\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        guard case .complete(let request) = HTTPRequest.parse(Data(text.utf8)) else { preconditionFailure("Didn't parse") }
        return await page.handle(request, from: "192.168.1.30")
    }

    private func json(_ response: HTTPResponse) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: response.body)) as? [String: Any] ?? [:]
    }

    @Test func phonesSeeTheSongbookByNameOnly() async throws {
        let page = LocalPage.songPicker(karaoke: karaoke(), hosts: [Self.host], code: "123456")
        let reply = await ask(page, "GET", "/api/songs")
        #expect(reply.status == 200)
        let songs = try #require(json(reply)["songs"] as? [[String: Any]])
        #expect(songs.count == 6)
        #expect(Set(songs.flatMap(\.keys)) == ["id", "title", "credit", "album", "video", "lyrics"], "Names, and nothing else")
        #expect(await ask(page, "GET", "/api/songs", code: "000000").status == 401, "The code on the TV, as for the editing page")
    }

    @Test func aPhoneAddsASongWithoutMovingTheTV() async throws {
        let karaoke = karaoke()
        karaoke.open(.artists)
        let page = LocalPage.songPicker(karaoke: karaoke, hosts: [Self.host], code: "123456")
        let reply = await ask(page, "POST", "/api/queue", body: #"{"id":"s4"}"#)
        #expect(reply.status == 200)
        #expect(karaoke.stage.state.song?.id == "s4", "Nothing was on: it's on stage")
        #expect(karaoke.places == [.home, .artists], "The TV stays where it was")
        #expect(karaoke.notice == "A phone added \u{201C}Mr. Blue Sky\u{201D}.")
        #expect(page.lastChange != nil, "The TV can say when a phone last added one")
        _ = await ask(page, "POST", "/api/queue", body: #"{"id":"s1"}"#)
        let stage = json(await ask(page, "GET", "/api/queue"))
        #expect((stage["queue"] as? [[String: Any]])?.map { $0["title"] as? String } == ["Dancing Queen"])
        #expect(await ask(page, "POST", "/api/queue", body: #"{"id":"nope"}"#).status == 422)
        #expect(await ask(page, "POST", "/api/queue", body: "garbage").status == 422)
    }

    @Test func phonesCantFloodTheQueue() async throws {
        let karaoke = karaoke()
        let page = LocalPage.songPicker(karaoke: karaoke, hosts: [Self.host], code: "123456")
        // Filled straight (a phone's request each time would be the same, more slowly).
        let song = try #require(karaoke.songbook.songs.first)
        karaoke.stage.add(song)
        for _ in 0..<SongPickerAPI.mostQueued { karaoke.stage.add(song) }
        let refused = await ask(page, "POST", "/api/queue", body: #"{"id":"s1"}"#)
        #expect(refused.status == 422 && karaoke.stage.queue.count == SongPickerAPI.mostQueued)
    }

    @Test func onlyWhileItsOnAndOnlyWhereOffered() async {
        let off = karaoke(phones: false)
        let page = LocalPage.songPicker(karaoke: off, hosts: [Self.host], code: "123456")
        #expect(await ask(page, "POST", "/api/queue", body: #"{"id":"s1"}"#).status == 422, "Turned off: nothing gets in")
        #expect(off.homeItems.contains(.phones))
        let web = KaraokeModel(session: Songs.session(), deck: deck)
        web.setPhonesAllowed(true)
        #expect(!web.phonesAllowed && !web.homeItems.contains(.phones), "A front end that can't serve the page doesn't offer it")
        let karaoke = karaoke()
        karaoke.leave()
        #expect(!karaoke.phonesAllowed, "Leaving turns it off")
    }

    @Test func thePageShowsNamesOnlyAsText() {
        #expect(!SongPickerHTML.page.contains("innerHTML") && !SongPickerHTML.page.contains("outerHTML")
                && !SongPickerHTML.page.contains("insertAdjacentHTML") && !SongPickerHTML.page.contains("document.write"))
        #expect(!SongPickerHTML.page.contains("http://") && !SongPickerHTML.page.contains("https://"), "Nothing fetched from elsewhere")
        #expect(!SongPickerHTML.page.contains("localStorage") && !SongPickerHTML.page.contains("sessionStorage"), "Nothing kept on the phone")
    }
}
