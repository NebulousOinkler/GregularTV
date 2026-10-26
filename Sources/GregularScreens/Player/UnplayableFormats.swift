import GregularCore

/// What this device's players turned out not to decode, this session: in
/// memory only, forgotten when the app closes, so an update to the device
/// gets a fresh chance.
///
/// A device says what it plays (`PlayableFormats`), and a failure to decode
/// corrects it. Each one rules out one format the failed stream carried, so
/// the next request asks the server for something else: another player, a
/// conversion of the sound, then of the video. Never one of the safest
/// formats (`StreamSource.safestFormats`), which every conversion ends up
/// as. A stream that carried only the safest formats and still won't play
/// leaves nothing to rule out. And no more than `mostPerPlayer` are ruled
/// out for a player, so it ends even with a server that names a different
/// format each time: the retries after a decode failure don't wait, so an
/// endless list would be endless requests.
struct UnplayableFormats {
    /// Each player's formats ruled out, for `StreamRequest.unplayable`.
    private(set) var byPlayer: [MediaStream.Player: Set<MediaFormat>] = [:]

    /// The most formats ruled out for one player in a session: far more than
    /// a device claims wrongly (a file carries two).
    static let mostPerPlayer = 8

    /// `contents` couldn't be decoded on `player`: rules out the first of its
    /// formats that isn't one of the `safest` and isn't ruled out already
    /// (the sound first: cheaper to convert, if it's the one at fault; if it
    /// wasn't, the next failure rules out the video). False if there's none,
    /// or `mostPerPlayer` are ruled out already: nothing's left to try.
    mutating func learn(from contents: StreamContents, on player: MediaStream.Player, safest: Set<MediaFormat>) -> Bool {
        let ruledOut = byPlayer[player, default: []]
        guard ruledOut.count < Self.mostPerPlayer else { return false }
        let isSafe = { (format: MediaFormat) in safest.contains { $0.kind == format.kind && $0.codec == format.codec } }
        guard let culprit = contents.formats.first(where: { !isSafe($0) && !ruledOut.contains($0) }) else { return false }
        byPlayer[player, default: []].insert(culprit)
        return true
    }
}
