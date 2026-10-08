import Foundation
import GregularCore
import Testing
@testable import GregularScreens

// Karaoke's behaviour, without drawing it: the songbook, the bouncing
// ball, the stage and the menus.

/// A song deck with no sound: it records what it's told. Loads finish at
/// once, or, while `holdsLoads`, when `finishLoads()` is called.
@MainActor final class FakeSongDeck: SongDeck {
    final class File: SongFile {
        let url: URL
        init(url: URL) { self.url = url }
    }

    struct Unloadable: Error {}

    private(set) var loads: [URL] = []
    private(set) var cued: URL?
    private(set) var isPlaying = false
    private(set) var restarts = 0
    var holdsLoads = false
    var position: TimeInterval = 0
    var onFinish: (() -> Void)?
    private var held: [CheckedContinuation<Void, Never>] = []

    func load(_ url: URL, mostBytes: Int) async throws -> any SongFile {
        loads.append(url)
        if holdsLoads { await withCheckedContinuation { held.append($0) } }
        try Task.checkCancellation()
        if url.lastPathComponent.hasPrefix("broken") { throw Unloadable() }
        return File(url: url)
    }

    func finishLoads() {
        let waiting = held
        held = []
        waiting.forEach { $0.resume() }
    }

    func cue(_ file: any SongFile) {
        cued = (file as? File)?.url
        isPlaying = false
    }
    func play() { isPlaying = true }
    func pause() { isPlaying = false }
    func restart() { restarts += 1 }
    func clear() {
        cued = nil
        isPlaying = false
    }

    /// The song on plays to its end.
    func finishSong() { onFinish?() }
}

/// A server whose songs all play as they are, except those named `unplayable`.
final class FakeSongServer: LyricsSource, OriginalFiles, @unchecked Sendable {
    let unplayable: Set<String>
    let lyrics: [String: SyncedLyrics]
    private let lock = NSLock()
    private var asked: [String] = []
    var lyricsAskedFor: [String] { lock.withLock { asked } }

    init(unplayable: Set<String> = [], lyrics: [String: SyncedLyrics] = [:]) {
        self.unplayable = unplayable
        self.lyrics = lyrics
    }

    func originalFile(of item: MediaItem) async throws -> URL? {
        unplayable.contains(item.id) ? nil : URL(string: "https://tv.invalid/\(item.id)")
    }

    func download(_ url: URL, mostBytes: Int) async throws -> Data {
        Data(url.lastPathComponent.utf8)
    }

    func checkDownload(_ url: URL) throws {}

    func lyrics(for itemID: String) async throws -> SyncedLyrics? {
        lock.withLock { asked.append(itemID) }
        return lyrics[itemID]
    }
}

enum Songs {
    static func song(_ id: String, _ title: String, by artists: [String] = ["ABBA"], album: String? = "Arrival",
                     kind: MediaItem.Kind = .song, lyrics: Bool = true, folders: [String] = [], container: String? = "mp3") -> MediaItem {
        MediaItem(id: id, kind: kind, name: title, duration: 200, artists: artists, album: album, folders: folders,
                  hasLyrics: lyrics, container: container)
    }

    static let library = [
        song("s1", "Dancing Queen"),
        song("s2", "Knowing Me, Knowing You"),
        song("s3", "Waterloo", album: nil),
        song("s4", "Mr. Blue Sky", by: ["Electric Light Orchestra"], album: "Out of the Blue"),
        song("v1", "Africa", by: [], album: nil, kind: .video, lyrics: false, folders: ["Toto", "Toto IV"], container: "mp4"),
        song("s5", "Café del Mar", by: ["Energy 52"], album: nil, lyrics: false),
    ]

    @MainActor static func session(_ items: [MediaItem] = library, server: FakeSongServer = FakeSongServer(),
                                   onExit: @escaping @MainActor (SpecialModeSession) -> Void = { _ in }) -> SpecialModeSession {
        SpecialModeSession(mode: SpecialMode(id: "karaoke"), programmes: items, formats: .appleTV, media: server, onExit: onExit)
    }
}

struct SongbookTests {
    let book = Songbook(Songs.library, formats: .appleTV)

    @Test func songsComeFromTagsOrFolders() throws {
        let africa = try #require(book.songs.first { $0.id == "v1" })
        #expect((africa.artist, africa.album, africa.isVideo, africa.hasLyrics) == ("Toto", "Toto IV", true, true),
                "Artist/Album folders; a video's words are in the picture")
        let flat = Songbook.Song(Songs.song("x", "Loose", by: [], album: nil, folders: ["Toto"]))
        #expect((flat.artist, flat.album) == ("Toto", nil), "Artist/Title folders")
        let nowhere = Songbook.Song(Songs.song("y", "Lost", by: [], album: nil))
        #expect(nowhere.artist == KaraokeText.unknownArtist)
        let duet = Songbook.Song(Songs.song("z", "Duet", by: ["Elton John", "Kiki Dee"]))
        #expect((duet.artist, duet.credit) == ("Elton John", "Elton John, Kiki Dee"), "Grouped by the first, credited to all")
    }

    @Test func onlyFilesThatPlayAsTheyAreAreListed() {
        let book = Songbook([
            Songs.song("ok", "Fine"),
            Songs.song("ogg", "Nope", container: "ogg"),
            Songs.song("mkv", "Nope", kind: .musicVideo, container: "mkv"),
            MediaItem(id: "film", kind: .movie, name: "A Film", duration: 6000),
        ], formats: .appleTV)
        #expect(book.songs.map(\.id) == ["ok"])
    }

    @Test func artistsAlbumsAndSongsAreInOrder() throws {
        #expect(book.songs.map(\.title) == ["Africa", "Café del Mar", "Dancing Queen", "Knowing Me, Knowing You", "Mr. Blue Sky", "Waterloo"])
        #expect(book.artists.map(\.name) == ["ABBA", "Electric Light Orchestra", "Energy 52", "Toto"])
        let abba = try #require(book.artist(named: "ABBA"))
        #expect(abba.albums.map(\.title) == ["Arrival", nil], "Songs on no album last")
        #expect(abba.songCount == 3)
        #expect(book.albums.map(\.title) == ["Arrival", "Out of the Blue", "Toto IV"])
    }

    @Test func searchMatchesEveryWordWhateverTheCaseOrAccents() {
        #expect(book.search("knowing abba").map(\.id) == ["s2"])
        #expect(book.search("CAFE").map(\.id) == ["s5"])
        #expect(book.search("toto iv").map(\.id) == ["v1"], "By album")
        #expect(book.search("  ").isEmpty)
    }

    @Test func surprisesHaveSomethingToSingAlongTo() {
        var random = SystemRandomNumberGenerator()
        for _ in 0..<20 { #expect(book.surprise(using: &random)?.id != "s5") }
        let onlyQuiet = book.songs.filter { $0.id == "s5" }
        #expect(book.surprise(from: onlyQuiet, using: &random)?.id == "s5", "Unless that's all there is")
    }
}

struct LyricsTimelineTests {
    typealias Word = SyncedLyrics.Word

    /// Two word-timed lines after an intro, a gap, then a line-timed one.
    let timeline = LyricsTimeline(SyncedLyrics(lines: [
        .init(start: 10, text: "You can dance", words: [Word(range: 0..<3, start: 10, end: 11), Word(range: 4..<7, start: 11), Word(range: 8..<13, start: 12)]),
        .init(start: 14, text: "You can jive", words: [Word(range: 0..<3, start: 14), Word(range: 4..<7, start: 15), Word(range: 8..<12, start: 16)]),
        .init(start: 18, text: ""),
        .init(start: 40, text: "Having the time of your life"),
        .init(start: 44, text: "See that girl"),
    ]))

    @Test func theIntroCountsIn() {
        #expect(timeline.moment(at: 5).countdown == nil, "Too soon")
        #expect(timeline.moment(at: 6.5).countdown == 4)
        #expect(timeline.moment(at: 9.2).countdown == 1)
        let intro = timeline.moment(at: 9.2)
        #expect(intro.line == nil && intro.next == 0 && intro.ball == nil)
    }

    @Test func theBackdropPulsesAsEachWordStarts() {
        #expect(timeline.pulse(at: 11) == 1)
        #expect(abs(timeline.pulse(at: 11 + LyricsTimeline.pulseLength) - exp(-1)) < 1e-9)
        #expect(timeline.pulse(at: 5) == 0 && timeline.pulse(at: 19) == 0, "Not before the singing, nor in a gap")
        #expect(timeline.pulse(at: 40) == 1, "Lines timed: as each line starts")
    }

    @Test func theBallLandsOnEachWordAsItsSung() throws {
        let moment = timeline.moment(at: 11.5)
        #expect(moment.line == 0 && moment.next == 1)
        let ball = try #require(moment.ball)
        #expect(ball.from.range == 4..<7 && ball.to?.range == 8..<13 && ball.progress == 0.5)
        #expect(moment.sung == 5.5, "Half way through \"can\"")
        #expect(timeline.moment(at: 10.5).sung == 1.5, "Each word's own end when it has one")
        #expect(timeline.moment(at: 13).ball?.to == nil, "On the last word, it stays")
        #expect(timeline.moment(at: 13).sung == 13)
    }

    @Test func aBlankLineEndsTheOneBefore() {
        let gap = timeline.moment(at: 25)
        #expect(gap.line == nil && gap.next == 3 && gap.countdown == nil)
        #expect(timeline.moment(at: 37).countdown == 3, "After a quiet stretch, the next line counts in")
    }

    @Test func withOnlyLinesTimedTheBallHopsLineToLine() throws {
        let moment = timeline.moment(at: 42)
        #expect(moment.line == 3 && moment.sung == 28, "The whole line lights up")
        let ball = try #require(moment.ball)
        #expect(ball.from == .init(line: 3, range: 0..<6) && ball.to == .init(line: 4, range: 0..<3) && ball.progress == 0.5)
        #expect(timeline.moment(at: 43).countdown == nil, "No countdown between lines sung one after another")
    }
}

@MainActor
struct KaraokeStageTests {
    let deck = FakeSongDeck()
    let book = Songbook(Songs.library, formats: .appleTV)

    private func song(_ id: String) throws -> Songbook.Song {
        try #require(book.songs.first { $0.id == id })
    }

    private func stage(_ server: FakeSongServer = FakeSongServer()) -> KaraokeStage {
        KaraokeStage(deck: deck, media: server)
    }

    @Test func aSongLoadsWholeThenWaitsForPlay() async throws {
        let lyrics = SyncedLyrics(lines: [.init(start: 1, text: "Friday night")])
        let server = FakeSongServer(lyrics: ["s1": lyrics])
        let stage = stage(server)
        deck.holdsLoads = true
        stage.add(try song("s1"))
        #expect(stage.state == .loading(try song("s1")), "Get ready!")
        try await waitUntil(2) { deck.loads.count == 1 }
        deck.finishLoads()
        try await waitUntil(2) { stage.state != .loading(try! song("s1")) }
        #expect(stage.state == .ready(try song("s1")) && deck.cued?.lastPathComponent == "s1" && !deck.isPlaying)
        #expect(stage.lyrics == LyricsTimeline(lyrics))
        stage.playOrPause()
        #expect(stage.state == .singing(try song("s1")) && deck.isPlaying)
        stage.playOrPause()
        #expect(stage.state == .paused(try song("s1")) && !deck.isPlaying)
    }

    @Test func onlySongsWithLyricsAskForThem() async throws {
        let server = FakeSongServer()
        let stage = stage(server)
        for id in ["v1", "s5", "s1"] { stage.add(try song(id)) }
        for _ in 0..<3 {
            try await waitUntil(2) { if case .ready = stage.state { true } else { false } }
            stage.skip()
        }
        #expect(server.lyricsAskedFor == ["s1"], "Not a video, nor a song the server has none for")
    }

    @Test func theNextSongLoadsWhileThisOnePlays() async throws {
        let stage = stage()
        stage.add(try song("s1"))
        stage.add(try song("s2"))
        try await waitUntil(2) { deck.loads.count == 2 }
        #expect(deck.loads.map(\.lastPathComponent) == ["s1", "s2"], "One at a time: the next once this one's loaded")
        stage.playOrPause()
        deck.finishSong()
        try await waitUntil(2) { stage.state == .ready(try! song("s2")) }
        #expect(deck.loads.count == 2, "Already loaded: no wait, and not fetched again")
        #expect(stage.queue.isEmpty)
        deck.finishSong()
        #expect(stage.state == .idle && deck.cued == nil, "Nothing left: nothing on, nothing held")
    }

    @Test func changingWhatsNextChangesWhatLoads() async throws {
        let stage = stage()
        stage.add(try song("s1"))
        try await waitUntil(2) { stage.state == .ready(try! song("s1")) }
        deck.holdsLoads = true
        stage.add(try song("s2"))
        stage.add(try song("s3"))
        stage.move(at: 1, by: -1)
        #expect(stage.queue.map(\.id) == ["s3", "s2"])
        try await waitUntil(2) { deck.loads.last?.lastPathComponent == "s3" }
        deck.holdsLoads = false
        deck.finishLoads()
        stage.remove(at: 0)
        #expect(stage.queue.map(\.id) == ["s2"])
        try await waitUntil(2) { deck.loads.last?.lastPathComponent == "s2" }
    }

    @Test func skippingASongStillLoadingStopsItsFetch() async throws {
        let stage = stage()
        deck.holdsLoads = true
        stage.add(try song("s1"))
        stage.add(try song("s2"))
        try await waitUntil(2) { deck.loads.count == 1 }
        stage.skip()
        try await waitUntil(2) { deck.loads.count == 2 }
        #expect(stage.state == .loading(try song("s2")))
        deck.finishLoads()
        try await waitUntil(2) { stage.state == .ready(try! song("s2")) }
        #expect(stage.notice == nil, "Skipped on purpose: nothing to say")
    }

    @Test func aSongThatWontLoadIsSkipped() async throws {
        let server = FakeSongServer(unplayable: ["s1"])
        let stage = stage(server)
        var unplayable: [String] = []
        stage.onUnplayable = { unplayable.append($0.id) }
        stage.add(try song("s1"))
        stage.add(try song("s2"))
        try await waitUntil(2) { stage.state == .ready(try! song("s2")) }
        #expect(unplayable == ["s1"])
        #expect(stage.notice == KaraokeText.skipped(try song("s1")))
    }

    @Test func restartSkipAndStop() async throws {
        let stage = stage()
        stage.add(try song("s1"))
        stage.add(try song("s2"))
        try await waitUntil(2) { stage.state == .ready(try! song("s1")) }
        stage.restart()
        #expect(deck.restarts == 0, "Nothing to restart on a title card")
        stage.playOrPause()
        stage.restart()
        #expect(try deck.restarts == 1 && stage.state == .singing(song("s1")))
        stage.skip()
        try await waitUntil(2) { stage.state == .ready(try! song("s2")) }
        stage.stop()
        #expect(stage.state == .idle && stage.queue.isEmpty && deck.cued == nil)
    }
}

@MainActor
struct KaraokeModelTests {
    let deck = FakeSongDeck()

    private func model(onExit: @escaping @MainActor (SpecialModeSession) -> Void = { _ in }) -> KaraokeModel {
        KaraokeModel(session: Songs.session(onExit: onExit), deck: deck)
    }

    @Test func itOpensOnTheThemesAndAThemeMustBeChosen() {
        let karaoke = model()
        #expect(karaoke.places == [.themes])
        #expect(!karaoke.canGoBack && karaoke.place?.title == KaraokeText.pickATheme)
        karaoke.back()
        #expect(karaoke.places == [.themes], "Nothing behind it yet")
        karaoke.preview(.vegasLounge)
        #expect(karaoke.shownTheme == .vegasLounge && karaoke.menuMusic == .vegasLounge, "A highlighted box samples its look and tune")
        karaoke.choose(.bubblegumPop)
        #expect(karaoke.places == [.home] && karaoke.theme == .bubblegumPop && karaoke.shownTheme == .bubblegumPop)
        karaoke.choose(.themes)
        karaoke.choose(.karaokeBar)
        #expect(karaoke.places == [.home] && karaoke.theme == .karaokeBar, "Changing it goes back to the menu")
    }

    @Test func backNeverLeavesKaraoke() {
        let karaoke = model()
        karaoke.choose(.neonDisco)
        karaoke.choose(.artists)
        karaoke.open(.artist("ABBA"))
        karaoke.back()
        karaoke.back()
        #expect(karaoke.places == [.home])
        #expect(!karaoke.canGoBack)
        karaoke.back()
        #expect(karaoke.places == [.home], "Only Leave Karaoke leaves")
    }

    @Test func theFirstSongGoesStraightOnStage() async throws {
        let karaoke = model()
        karaoke.choose(.neonDisco)
        karaoke.open(.songs)
        let songs = karaoke.songs
        #expect(songs.count == 6)
        karaoke.queue(songs[2])
        #expect(karaoke.places.isEmpty && !karaoke.isAttract)
        try await waitUntil(2) { if case .ready = karaoke.stage.state { true } else { false } }
        #expect(karaoke.places.isEmpty && !karaoke.isAttract && karaoke.menuMusic == .neonDisco, "The tune plays on the title card")
        karaoke.perform(try #require(RemoteControls.karaokeStage[.playPause]))
        #expect(karaoke.menuMusic == nil, "And fades for the song")

        karaoke.perform(try #require(RemoteControls.karaokeStage[.menu]))
        #expect(karaoke.places == [.home])
        #expect(karaoke.homeItems.prefix(3) == [.backToSong, .restartSong, .skipSong])
        karaoke.open(.songs)
        karaoke.queue(songs[3])
        #expect(karaoke.notice == KaraokeText.queued(songs[3], place: 1) && karaoke.places == [.home, .songs], "Queued: browsing carries on")
        karaoke.perform(try #require(RemoteControls.karaokeMenus[.menu]))
        karaoke.perform(try #require(RemoteControls.karaokeMenus[.menu]))
        #expect(karaoke.places.isEmpty && !karaoke.isAttract, "Back from the menu: the song")
    }

    @Test func withNothingQueuedTheStageIsTheAttractScreen() async throws {
        let karaoke = model()
        karaoke.choose(.neonDisco)
        karaoke.surpriseMe()
        try await waitUntil(2) { if case .ready = karaoke.stage.state { true } else { false } }
        karaoke.stage.playOrPause()
        deck.finishSong()
        #expect(karaoke.isAttract && karaoke.menuMusic == .neonDisco)
        karaoke.leaveAttract()
        #expect(karaoke.places == [.home] && karaoke.homeItems.first == .artists)
    }

    @Test func listsShowTheirSongs() {
        let karaoke = model()
        karaoke.choose(.neonDisco)
        karaoke.choose(.search)
        karaoke.query = "abba"
        #expect(karaoke.songs.count == 3)
        karaoke.back()
        karaoke.open(.search)
        #expect(karaoke.query.isEmpty && karaoke.songs.isEmpty, "A new search starts empty")
        let album = karaoke.songbook.albums[0]
        karaoke.open(.album(album))
        #expect(karaoke.songs == album.songs)
    }

    @Test func aSongThatWontLoadLeavesTheSongbook() async throws {
        let session = Songs.session(server: FakeSongServer(unplayable: ["s1"]))
        let karaoke = KaraokeModel(session: session, deck: deck)
        karaoke.choose(.neonDisco)
        karaoke.queue(try #require(karaoke.songbook.songs.first { $0.id == "s1" }))
        try await waitUntil(2) { karaoke.stage.state == .idle && karaoke.stage.notice != nil }
        #expect(!karaoke.songbook.songs.contains { $0.id == "s1" })
    }

    @Test func leavingLetsGoOfEverySong() {
        var left = false
        let karaoke = model { _ in left = true }
        karaoke.choose(.neonDisco)
        karaoke.surpriseMe()
        karaoke.leave()
        #expect(left && karaoke.stage.state == .idle && deck.cued == nil)
        #expect(karaoke.leaveConfirmation.action == KaraokeModel.HomeItem.leave.title)
    }
}

/// Every theme's tune and sound effects, as each front end's synthesizer gets them.
struct KaraokeMusicTests {
    @Test(arguments: KaraokeTheme.allCases)
    func eachThemeHasATuneLongEnoughNotToSoundLikeALoop(theme: KaraokeTheme) {
        let music = theme.music
        let loop = music.loop
        #expect(music.duration >= 25 && music.duration <= 60, "Half a minute or so before it repeats")
        #expect(loop.allSatisfy { $0.at >= 0 && $0.at < music.duration && $0.length > 0 && (0...1).contains($0.gain) })
        #expect(music.intro.allSatisfy { $0.at < music.introDuration } && !music.intro.isEmpty, "A pickup into the loop")
        #expect(loop.contains { $0.sound == .drum(.kick) } || loop.contains { $0.sound == .drum(.brush) }, "A beat")
        #expect(Set(loop.compactMap { if case .note(let part, _) = $0.sound { part } else { nil } }).count >= 4,
                "Bass, chords and a tune at least")
        #expect(loop.allSatisfy { (-1...1).contains($0.pan) })
    }

    @Test(arguments: KaraokeTheme.allCases)
    func everyNoteHasAnInstrumentAndASpeakerCanPlayIt(theme: KaraokeTheme) {
        let music = theme.music
        let events = music.intro + music.loop + KaraokeMusic.Effect.allCases.flatMap { music.notes(for: $0) }
        for event in events {
            guard case .note(let part, let note) = event.sound else { continue }
            #expect(music.patches[part] != nil, "\(part) has no instrument")
            #expect((24...108).contains(note), "\(part) note \(note)")
        }
        for patch in music.patches.values {
            #expect(!patch.waves.isEmpty && patch.level > 0 && patch.level <= 1 && (-1...1).contains(patch.pan))
            #expect(patch.attack > 0 && patch.decay > 0 && patch.release > 0, "No clicks")
        }
        #expect(music.patches[.blip]?.group == .effects && music.patches[.fanfare]?.group == .effects)
    }

    @Test(arguments: KaraokeTheme.allCases)
    func everyEffectSounds(theme: KaraokeTheme) {
        for effect in KaraokeMusic.Effect.allCases {
            let notes = theme.music.notes(for: effect)
            #expect(!notes.isEmpty && notes.allSatisfy { $0.at >= 0 && $0.at < 4 && (0...1).contains($0.gain) }, "\(effect)")
        }
        let blips = (0..<10).map { theme.music.notes(for: .move, step: $0)[0].sound }
        #expect(Set(blips.prefix(8)).count == 8 && blips[9] == blips[7], "Climbing the scale, then staying at the top")
    }

    @Test func eachThemeSoundsItsOwn() {
        let tempos = Set(KaraokeTheme.allCases.map(\.music.tempo))
        #expect(tempos.count == KaraokeTheme.allCases.count)
    }

    @Test func waitingTurnsTheDrumsAndTuneDownUnderTheChords() {
        #expect(KaraokeMusic.Group.allCases.allSatisfy { KaraokeMusic.gain(of: $0, in: .full) == 1 })
        #expect(KaraokeMusic.gain(of: .pad, in: .waiting) == 1 && KaraokeMusic.gain(of: .effects, in: .waiting) == 1)
        #expect(KaraokeMusic.gain(of: .drums, in: .waiting) < 0.5 && KaraokeMusic.gain(of: .lead, in: .waiting) < 0.5)
    }

    @Test func aLineOfNotesReadsAsWritten() {
        let notes = Score.notes(in: "0 - - 7 . x - . . . . . . . 12 -")
        #expect(notes.map(\.step) == [0, 3, 5, 14])
        #expect(notes.map(\.steps) == [3, 1, 2, 2])
        #expect(notes.map(\.value) == [0, 7, nil, 12])
    }

    @Test func offBeatsSwing() {
        let straight = Score(tempo: 120, root: 48)
        let swung = Score(tempo: 120, root: 48, swing: 0.33, swingSteps: 2)
        #expect(straight.time(bar: 0, step: 2) == 0.25)
        #expect(abs(swung.time(bar: 0, step: 2) - (0.25 + 0.33 * 0.25)) < 1e-9)
        #expect(swung.time(bar: 1, step: 4) == straight.time(bar: 1, step: 4), "On the beat: as written")
    }

    @Test func theBlipClimbsWhileMovesComeQuickly() {
        var ladder = BlipLadder()
        #expect([0, 0.2, 0.4, 0.6].map { ladder.step(at: $0) } == [0, 1, 2, 3])
        #expect(ladder.step(at: 2) == 0, "A pause starts again at the bottom")
        for time in stride(from: 2.1, to: 4, by: 0.1) { _ = ladder.step(at: time) }
        #expect(ladder.step(at: 4.05) == 7, "Never past the top")
    }
}

/// The pictures drawn for songs and albums, and the letters long lists jump by.
struct KaraokeCoverTests {
    @Test func theSameNameAlwaysGetsTheSamePicture() {
        let cover = KaraokeCover("Dancing Queen", by: "ABBA")
        #expect(cover == KaraokeCover("Dancing Queen", by: "ABBA"))
        #expect(cover.initials == "DQ" && cover.back != cover.front && cover.angle % 45 == 0)
        #expect((0..<KaraokeCover.colourCount).contains(cover.back) && (0..<KaraokeCover.colourCount).contains(cover.front))
    }

    @Test func namesGetAllSortsOfPictures() {
        let covers = (0..<200).map { KaraokeCover("Song \($0)", by: "Someone") }
        #expect(Set(covers.map(\.pattern)).count == KaraokeCover.Pattern.allCases.count)
        #expect(Set(covers.map(\.back)).count == KaraokeCover.colourCount)
        #expect(Set(covers.map(\.angle)).count == 4)
    }

    @Test func initialsAreTheFirstTwoWords() {
        #expect(KaraokeCover.initials(of: "Mr. Blue Sky") == "MB")
        #expect(KaraokeCover.initials(of: "Café del Mar") == "CD")
        #expect(KaraokeCover.initials(of: "(Don't Fear) the Reaper") == "DF")
        #expect(KaraokeCover.initials(of: "1999") == "1")
        #expect(KaraokeCover.initials(of: "!!!") == "")
    }

    @Test func longListsJumpByLetter() {
        let names = ["ABBA", "Africa", "Électrique", "Energy 52", "1999", "Zed"] + (0..<8).map { "Toto \($0)" }
        let letters = Songbook.letters(of: names)
        #expect(letters.map(\.letter) == ["A", "E", "#", "Z", "T"])
        #expect(letters.map(\.index) == [0, 2, 4, 5, 6])
        #expect(Songbook.letters(of: Array(names.prefix(6))).isEmpty, "A short list needs no letters")
        #expect(Songbook.letters(of: (0..<20).map { "Toto \($0)" }).isEmpty, "Nor does a list all under one letter")
        #expect(Songbook.letter(of: "  ñandú") == "N" && Songbook.letter(of: "") == "#")
    }
}

/// What the model tells a front end to show and play, beyond moving about.
@MainActor struct KaraokePresentationTests {
    let deck = FakeSongDeck()

    @Test func theHomeMenuIsInGroups() {
        let karaoke = KaraokeModel(session: Songs.session(), deck: deck, offersPhones: true)
        karaoke.choose(.neonDisco)
        #expect(karaoke.homeItems.filter { $0.group == .songs } == [.artists, .albums, .songs, .search, .surpriseMe, .queue])
        #expect(karaoke.homeItems.filter { $0.group == .more } == [.phones, .themes, .leave])
        #expect(karaoke.homeItems.allSatisfy { $0.group != .song }, "No song: no song controls")
    }

    @Test func theHintNamesOnlyButtonsThatDoSomething() async throws {
        let karaoke = KaraokeModel(session: Songs.session(), deck: deck)
        #expect(karaoke.menuControls.isEmpty, "On the first theme boxes, Menu and Play/Pause do nothing")
        karaoke.choose(.neonDisco)
        #expect(karaoke.menuControls.isEmpty, "Nor on the home menu with nothing on")
        karaoke.open(.songs)
        #expect(karaoke.menuControls.values.sorted { "\($0)" < "\($1)" } == [.stepBack])
        karaoke.queue(karaoke.songs[0])
        try await waitUntil(2) { if case .ready = karaoke.stage.state { true } else { false } }
        karaoke.perform(.openKaraokeMenu)
        #expect(Set(karaoke.menuControls.values) == [.stepBack, .playOrPauseSong])
    }

    @Test func theTuneWaitsSoftlyUnderATitleCard() async throws {
        let karaoke = KaraokeModel(session: Songs.session(), deck: deck)
        karaoke.choose(.neonDisco)
        #expect(karaoke.musicMood == .full)
        karaoke.surpriseMe()
        try await waitUntil(2) { if case .ready = karaoke.stage.state { true } else { false } }
        #expect(karaoke.musicMood == .waiting)
        karaoke.perform(.openKaraokeMenu)
        #expect(karaoke.musicMood == .full, "A menu over it: full")
    }

    @Test func queuedAndFinishedSongsAreCounted() async throws {
        let karaoke = KaraokeModel(session: Songs.session(), deck: deck)
        karaoke.choose(.neonDisco)
        let song = karaoke.songbook.songs[0]
        karaoke.queue(song)
        karaoke.surpriseMe()
        #expect(karaoke.songsQueued == 2 && karaoke.lastQueued != nil)
        try await waitUntil(2) { if case .ready = karaoke.stage.state { true } else { false } }
        karaoke.stage.playOrPause()
        karaoke.stage.skip()
        #expect(karaoke.stage.songsFinished == 0, "Skipped isn't finished")
        try await waitUntil(2) { if case .ready = karaoke.stage.state { true } else { false } }
        karaoke.stage.playOrPause()
        let sung = karaoke.stage.state.song
        deck.finishSong()
        #expect(karaoke.stage.songsFinished == 1 && karaoke.stage.lastFinished == sung)
    }
}

/// Lines as words and gaps, as both front ends draw them.
struct LyricsSegmentTests {
    @Test func aLineIsWordsAndTheGapsBetween() {
        let timeline = LyricsTimeline(SyncedLyrics(lines: [
            .init(start: 0, text: "Oh, la la!", words: [.init(range: 0..<3, start: 0), .init(range: 4..<6, start: 1), .init(range: 7..<10, start: 2)]),
            .init(start: 5, text: "  Two  words "),
        ]))
        let timed = timeline.segments(ofLine: 0)
        #expect(timed.map(\.text) == ["Oh,", " ", "la", " ", "la!"])
        #expect(timed.map(\.isWord) == [true, false, true, false, true])
        #expect(timeline.segments(ofLine: 1).filter(\.isWord).map(\.text) == ["Two", "words"], "Untimed: between spaces")
        #expect(timeline.segments(ofLine: 1).map(\.text).joined() == "  Two  words ", "Nothing lost")
        #expect(timed[2].fill(sung: 5) == 0.5 && timed[0].fill(sung: 5) == 1 && timed[4].fill(sung: 5) == 0)
    }
}
